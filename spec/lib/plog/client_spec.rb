require 'spec_helper'

describe Plog::Client do

  let(:chunk_size) { 5 }
  subject { Plog::Client.new(:chunk_size => chunk_size) }

  let(:udp_socket) do
    double(UDPSocket).tap do |udp_socket|
      udp_socket.stub(:send)
      udp_socket.stub(:close)
    end
  end

  before do
    UDPSocket.stub(:new).and_return(udp_socket)
  end

  describe '#send' do
    let(:message) { 'xxx' }

    it "contacts the given host and port" do
      udp_socket.should_receive(:send).with(anything(), 0, subject.host, subject.port)
      subject.send(message)
    end

    it "encodes the message id, message length and chunk size" do
      Plog::Packets::MultipartMessage.should_receive(:encode).with(
        0, message.length, chunk_size, anything(), anything(), message).and_call_original
      subject.send(message)
    end

    it "returns an monotonically increasing message id" do
      expect(subject.send(message)).to eq(0)
      expect(subject.send(message)).to eq(1)
    end

    it "reuses the same socket" do
      UDPSocket.should_receive(:new).once.and_return(udp_socket)
      2.times { subject.send(message) }
    end

    describe 'message id' do
      before do
        @message_ids = []
        Plog::Packets::MultipartMessage.stub(:encode) do |message_id, _, _, _, _, _|
          @message_ids << message_id
        end
      end

      it "encodes each message with a monotonically increasing message id" do
        5.times { subject.send(message) }
        expect(@message_ids).to eq((0...5).to_a)
      end
    end

    describe 'chunking' do
      let(:chunk_size) { 5 }
      let(:message) { 'AAAA' }
      let(:expected_chunks) { ['AAAA'] }

      before do
        @sent_datagrams = []
        Plog::Packets::MultipartMessage.stub(:encode) do |_, _, _, count, index, data|
          "#{count}:#{index}:#{data}"
        end
        udp_socket.stub(:send) do |datagram, _, _, _|
          @sent_datagrams << datagram
        end
      end

      def validate_datagrams
        # Reassemble the message and verify the counts and indexes.
        reassembled_message = ""
        @sent_datagrams.each_with_index do |datagram, datagram_index|
          count, index, data = datagram.split(':')
          expect(count.to_i).to eq(expected_chunks.count)
          expect(index.to_i).to eq(datagram_index)
          reassembled_message += data
        end
        # Verify that the message was sent as intended.
        expect(reassembled_message).to eq(message)
      end

      context "when the message length is lower than the chunk size" do
        let(:chunk_size) { 5 }
        let(:message) { "A" * (chunk_size - 1) }
        let(:expected_chunks)  { [message] }

        it "encodes the message and sends it as a single packet" do
          subject.send(message)
          validate_datagrams
        end
      end

      context "when the message is large than the chunk size" do
        let(:chunk_size) { 5 }
        let(:message) { "A" * (chunk_size + 1) }
        let(:expected_chunks)  { ["A" * chunk_size, "A"] }

        it "chunks the message and sends it as many packets" do
          subject.send(message)
          validate_datagrams
        end

      end
    end

    describe 'exceptions' do

      context "when the socket operation raises" do
        it "closes and re-opens the socket" do
          udp_socket.stub(:send).and_raise
          udp_socket.should_receive(:close).once
          expect { subject.send(message) }.to raise_error

          udp_socket.stub(:send) {}
          UDPSocket.should_receive(:new).once.and_return(udp_socket)
          subject.send(message)
        end
      end

    end

  end

end