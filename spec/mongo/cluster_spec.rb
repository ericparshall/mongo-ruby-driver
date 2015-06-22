require 'spec_helper'

describe Mongo::Cluster do

  let(:cluster) do
    described_class.new(ADDRESSES, TEST_OPTIONS)
  end

  describe '#==' do

    context 'when the other is a cluster' do

      context 'when the addresses are the same' do

        context 'when the options are the same' do

          let(:other) do
            described_class.new(ADDRESSES, TEST_OPTIONS)
          end

          it 'returns true' do
            expect(cluster).to eq(other)
          end
        end

        context 'when the options are not the same' do

          let(:other) do
            described_class.new([ '127.0.0.1:27017' ], TEST_OPTIONS.merge(:replica_set => 'test'))
          end

          it 'returns false' do
            expect(cluster).to_not eq(other)
          end
        end
      end

      context 'when the addresses are not the same' do

        let(:other) do
          described_class.new([ '127.0.0.1:27018' ], TEST_OPTIONS)
        end

        it 'returns false' do
          expect(cluster).to_not eq(other)
        end
      end
    end

    context 'when the other is not a cluster' do

      it 'returns false' do
        expect(cluster).to_not eq('test')
      end
    end
  end

  describe '#inspect' do

    let(:preference) do
      Mongo::ServerSelector.get
    end

    it 'displays the cluster seeds and topology' do
      expect(cluster.inspect).to include('topology')
      expect(cluster.inspect).to include('servers')
    end
  end

  describe '#replica_set_name' do

    let(:preference) do
      Mongo::ServerSelector.get
    end

    context 'when the option is provided' do

      let(:cluster) do
        described_class.new([ '127.0.0.1:27017' ], TEST_OPTIONS.merge(:connect => :replica_set,
                                                                      :replica_set => 'testing'))
      end

      it 'returns the name' do
        expect(cluster.replica_set_name).to eq('testing')
      end
    end

    context 'when the option is not provided' do

      let(:cluster) do
        described_class.new([ '127.0.0.1:27017' ], TEST_OPTIONS)
      end

      it 'returns nil' do
        expect(cluster.replica_set_name).to be_nil
      end
    end
  end

  describe '#scan!' do

    let(:preference) do
      Mongo::ServerSelector.get
    end

    let(:known_servers) do
      cluster.instance_variable_get(:@servers)
    end

    before do
      expect(known_servers.first).to receive(:scan!).and_call_original
    end

    it 'returns true' do
      expect(cluster.scan!).to be true
    end
  end

  describe '#servers' do

    context 'when topology is single', if: single_seed? do

      context 'when the server is a mongos', if: single_mongos?  do

        it 'returns the mongos' do
          expect(cluster.servers.size).to eq(1)
        end
      end

      context 'when the server is a replica set member', if: single_rs_member? do

        it 'returns the replica set member' do
          expect(cluster.servers.size).to eq(1)
        end
      end
    end

    context 'when the cluster has no servers' do

      let(:servers) do
        [nil]
      end

      before do
        cluster.instance_variable_set(:@servers, servers)
        cluster.instance_variable_set(:@topology, topology)
      end

      context 'when topology is Single' do

        let(:topology) do
          Mongo::Cluster::Topology::Single.new({})
        end

        it 'returns an empty array' do
          expect(cluster.servers).to eq([])
        end
      end

      context 'when topology is ReplicaSet' do

        let(:topology) do
          Mongo::Cluster::Topology::ReplicaSet.new({})
        end

        it 'returns an empty array' do
          expect(cluster.servers).to eq([])
        end
      end

      context 'when topology is Sharded' do

        let(:topology) do
          Mongo::Cluster::Topology::Sharded.new({})
        end

        it 'returns an empty array' do
          expect(cluster.servers).to eq([])
        end
      end

      context 'when topology is Unknown' do

        let(:topology) do
          Mongo::Cluster::Topology::Unknown.new({})
        end

        it 'returns an empty array' do
          expect(cluster.servers).to eq([])
        end
      end
    end
  end

  describe '#add' do

    context 'when topology is Single' do

      let(:topology) do
        Mongo::Cluster::Topology::Single.new({})
      end

      before do
        cluster.add('a')
      end

      it 'does not add discovered servers to the cluster' do
        expect(cluster.servers[0].address.seed).to_not eq('a')
      end
    end
  end

  describe '#remove' do

    let(:address_a) do
      Mongo::Address.new('127.0.0.1:27017')
    end

    let(:address_b) do
      Mongo::Address.new('127.0.0.1:27018')
    end

    let(:server_a) do
      Mongo::Server.new(address_a, cluster, Mongo::Event::Listeners.new)
    end

    let(:server_b) do
      Mongo::Server.new(address_b, cluster, Mongo::Event::Listeners.new)
    end

    let(:servers) do
      [ server_a, server_b ]
    end

    let(:addresses) do
      [ address_a, address_b ]
    end

    before do
      cluster.instance_variable_set(:@servers, servers)
      cluster.instance_variable_set(:@addresses, addresses)
      cluster.remove('127.0.0.1:27017')
    end

    it 'removes the host from the list of servers' do
      expect(cluster.instance_variable_get(:@servers)).to eq([server_b])
    end

    it 'removes the host from the list of addresses' do
      expect(cluster.instance_variable_get(:@addresses)).to eq([address_b])
    end
  end

  describe '#add_hosts' do

    let(:servers) do
      [nil]
    end

    let(:hosts) do
      ["127.0.0.1:27018"]
    end

    let(:description) do
      Mongo::Server::Description.new(double('address'), { 'hosts' => hosts })
    end

    before do
      cluster.instance_variable_set(:@servers, servers)
      cluster.instance_variable_set(:@topology, topology)
    end

    context 'when the topology allows servers to be added' do

      let(:topology) do
        double('topology').tap do |t|
          allow(t).to receive(:add_hosts?).and_return(true)
        end
      end

      it 'adds the servers' do
        expect(cluster).to receive(:add).once
        cluster.add_hosts(description)
      end
    end

    context 'when the topology does not allow servers to be added' do

      let(:topology) do
        double('topology').tap do |t|
          allow(t).to receive(:add_hosts?).and_return(false)
        end
      end

      it 'does not add the servers' do
        expect(cluster).not_to receive(:add)
        cluster.add_hosts(description)
      end
    end
  end

  describe '#remove_hosts' do

    let(:listeners) do
      Mongo::Event::Listeners.new
    end

    let(:address) do
      Mongo::Address.new('127.0.0.1:27017')
    end

    let(:server) do
      Mongo::Server.new(address, cluster, listeners)
    end

    let(:servers) do
      [ server ]
    end

    let(:hosts) do
      ["127.0.0.1:27018"]
    end

    let(:description) do
      Mongo::Server::Description.new(double('address'), { 'hosts' => hosts })
    end

    context 'when the topology allows servers to be removed' do

      context 'when the topology allows a specific server to be removed' do

        let(:topology) do
          double('topology').tap do |t|
            allow(t).to receive(:remove_hosts?).and_return(true)
            allow(t).to receive(:remove_server?).and_return(true)
          end
        end

        before do
          cluster.instance_variable_set(:@servers, servers)
          cluster.instance_variable_set(:@topology, topology)
        end

        it 'removes the servers' do
          expect(cluster).to receive(:remove).once
          cluster.remove_hosts(description)
        end
      end

      context 'when the topology does not allow a specific server to be removed' do

        let(:topology) do
          double('topology').tap do |t|
            allow(t).to receive(:remove_hosts?).and_return(true)
            allow(t).to receive(:remove_server?).and_return(false)
          end
        end

        before do
          cluster.instance_variable_set(:@servers, servers)
          cluster.instance_variable_set(:@topology, topology)
        end

        it 'removes the servers' do
          expect(cluster).not_to receive(:remove)
          cluster.remove_hosts(description)
        end
      end
    end

    context 'when the topology does not allow servers to be removed' do

      let(:topology) do
        double('topology').tap do |t|
          allow(t).to receive(:remove_hosts?).and_return(false)
        end
      end

      before do
        cluster.instance_variable_set(:@servers, servers)
        cluster.instance_variable_set(:@topology, topology)
      end

      it 'does not remove the servers' do
        expect(cluster).not_to receive(:remove)
        cluster.remove_hosts(description)
      end
    end
  end
end
