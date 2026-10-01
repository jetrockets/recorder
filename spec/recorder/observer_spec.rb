# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Recorder::Observer do
  # Throwaway models: `.recorder` registers callbacks, which outlive an example.
  def securities_model(name, &block)
    stub_const(name, Class.new(ApplicationRecord) { self.table_name = 'securities' }).tap do |model|
      model.include(described_class)
      model.class_eval(&block) if block
    end
  end

  describe '.recorder' do
    it 'raises when a subclass declares it again' do
      subclass = stub_const('Note', Class.new(Instrument))

      aggregate_failures do
        expect { subclass.recorder only: %i[name] }
          .to raise_error(ArgumentError, /already declared in Instrument/)
        expect(subclass.recorder_options).to equal(Instrument.recorder_options)
      end
    end

    it 'raises when a class declares it twice' do
      model = securities_model('TwiceDeclared') { recorder ignore: %i[name] }

      expect { model.recorder only: %i[name] }
        .to raise_error(ArgumentError, /already declared in TwiceDeclared/)
    end

    it 'raises when a parent declares it after a subclass' do
      parent = securities_model('LateParent')
      child = stub_const('EarlyChild', Class.new(parent) { recorder only: %i[name] })

      aggregate_failures do
        expect { parent.recorder ignore: %i[identifier] }
          .to raise_error(ArgumentError, /already declared in EarlyChild/)
        expect { child.create!(name: 'Facebook', identifier: 'FB') }.to change(Recorder::Revision, :count).by(1)
      end
    end

    it 'does not count a call that raised' do
      model = securities_model('Retried')

      aggregate_failures do
        expect { model.recorder changes: 42 }.to raise_error(ArgumentError, /`changes:`/)
        expect { model.recorder ignore: %i[identifier] }.not_to raise_error
        expect { model.create!(name: 'Facebook', identifier: 'FB') }.to change(Recorder::Revision, :count).by(1)
      end
    end

    it 'leaves the parent alone when a subclass declares it first' do
      parent = securities_model('Unrecorded')
      child = stub_const('RecordedChild', Class.new(parent) { recorder only: %i[name] })

      aggregate_failures do
        expect(parent.recorder_options).to eq({})
        expect { parent.create!(name: 'Facebook', identifier: 'FB') }.not_to change(Recorder::Revision, :count)
        expect { child.create!(name: 'Facebook', identifier: 'FB') }.to change(Recorder::Revision, :count).by(1)
      end
    end
  end

  describe '.recorder_options' do
    it 'is empty until .recorder is called' do
      model = securities_model('Undeclared')

      aggregate_failures do
        expect(model.recorder_options).to eq({})
        expect { model.create!(name: 'Facebook', identifier: 'FB') }.not_to change(Recorder::Revision, :count)
      end
    end

    it 'reaches a subclass that included Observer before its parent did' do
      parent = stub_const('LateIncluder', Class.new(ApplicationRecord) { self.table_name = 'securities' })
      child = stub_const('EarlyIncluder', Class.new(parent) { include Recorder::Observer })
      parent.include(described_class)
      parent.recorder ignore: %i[identifier updated_at]

      record = child.create!(name: 'Facebook', identifier: 'FB')

      snapshots = Recorder::Revision.where(item_id: record.id).map { |revision| revision.data['attributes'] }
      aggregate_failures do
        expect(snapshots.size).to eq(1)
        expect(snapshots.first.keys).not_to include('identifier', 'updated_at')
      end
    end

    it 'can be overridden on the class, building on super' do
      model = securities_model('ClassOverride')
      model.class_eval do
        recorder ignore: %i[identifier]

        def self.recorder_options
          super.merge(ignore: %i[identifier updated_at])
        end
      end
      record = model.create!(name: 'Facebook', identifier: 'FB')

      snapshot = Recorder::Revision.where(item_id: record.id).last.data['attributes']
      expect(snapshot.keys).not_to include('identifier', 'updated_at')
    end

    it 'keeps options declared with indifferent access' do
      options = {ignore: %i[identifier updated_at]}.with_indifferent_access
      model = securities_model('IndifferentInstrument') { recorder(options) }
      record = model.create!(name: 'Facebook', identifier: 'FB')

      snapshot = Recorder::Revision.where(item_id: record.id).last.data['attributes']
      expect(snapshot.keys).not_to include('identifier', 'updated_at')
    end
  end

  describe '#recorder_options' do
    it 'lets a subclass build its own options on its parent’s' do
      subclass = stub_const('Bill', Class.new(Instrument) do
        def recorder_options
          super.merge(ignore: [*super[:ignore], :settle_days])
        end
      end)
      bill = subclass.create!(name: 'Treasury', identifier: 'UST')

      snapshots = Recorder::Revision.where(item_id: bill.id).map { |revision| revision.data['attributes'] }
      aggregate_failures do
        expect(snapshots.size).to eq(1)
        expect(snapshots.first.keys).not_to include('identifier', 'updated_at', 'settle_days')
        expect(snapshots.first).to include('name' => 'Treasury')
        expect(Instrument.recorder_options[:ignore]).to eq(%i[identifier updated_at])
      end
    end
  end
end
