# frozen_string_literal: true

require 'rails_helper'

# An app's own revision class, named by `Recorder.config.revision_class`.
RSpec.describe Recorder, '.revision_class' do
  # The revisions each class defined here saw in its `after_create`.
  let(:created) { [] }

  def define_revision_class(name = 'AppRevision', &block)
    seen = created
    stub_const(name, Class.new(Recorder::Revision) { after_create { seen << self } }).tap do |klass|
      klass.class_eval(&block) if block
    end
  end

  # A throwaway observed model. It reads the setting when it includes
  # Recorder::Observer, as a model does when the app loads it.
  def observed_model(name = 'Ledger')
    stub_const(name, Class.new(ApplicationRecord) do
      self.table_name = 'securities'
      self.inheritance_column = nil
    end).tap do |model|
      model.include(Recorder::Observer)
      model.recorder
    end
  end

  def create_security
    Security.create!(name: 'Facebook', identifier: 'FB')
  end

  # Examples already run inside a transaction, so a rollback needs a savepoint
  # of its own.
  def roll_back
    ActiveRecord::Base.transaction(requires_new: true) do
      yield
      raise ActiveRecord::Rollback
    end
  end

  describe 'by default' do
    it 'is Recorder::Revision' do
      aggregate_failures do
        expect(described_class.revision_class).to equal(Recorder::Revision)
        expect(described_class.revision_class_name).to eq('::Recorder::Revision')
        expect(Security.reflect_on_association(:revisions).klass).to equal(Recorder::Revision)
      end
    end

    it 'writes and reads Recorder::Revision instances' do
      security = create_security

      aggregate_failures do
        expect(security.revisions.reload.map(&:class)).to eq([Recorder::Revision])
        expect(Recorder::Revision.last).to be_an_instance_of(Recorder::Revision)
      end
    end
  end

  describe 'a subclass set by name' do
    let!(:revision_class) { define_revision_class }

    before { described_class.config.revision_class = 'AppRevision' }

    it 'is the class revisions are written through' do
      expect(described_class.revision_class).to equal(revision_class)
    end

    it 'may be named with a leading ::' do
      described_class.config.revision_class = '::AppRevision'

      aggregate_failures do
        expect(described_class.revision_class).to equal(revision_class)
        expect(described_class.revision_class_name).to eq('::AppRevision')
      end
    end

    it 'is what the callbacks write, running its after_create' do
      security = create_security
      security.update!(name: 'Meta')
      security.destroy!

      aggregate_failures do
        expect(created.map(&:event)).to eq(%w[create update destroy])
        expect(created.map(&:class).uniq).to eq([revision_class])
        expect(created).to all(be_persisted)
      end
    end

    it 'is what Tape writes when called directly' do
      security = Security.create!(name: 'Facebook', identifier: 'FB')
      security.name = 'Meta'
      security.save!
      created.clear

      Recorder::Tape.new(security).record_update
      Recorder::Tape.record(item_type: 'Security', item_id: security.id, event: 'create', data: {attributes: {}})

      expect(created.map { |revision| [revision.class, revision.event] })
        .to eq([[revision_class, 'update'], [revision_class, 'create']])
    end

    it 'is what has_many :revisions returns on a model loaded after it was set' do
      model = observed_model
      record = model.create!(name: 'Facebook', identifier: 'FB')

      aggregate_failures do
        expect(model.reflect_on_association(:revisions).klass).to equal(revision_class)
        expect(model.find(record.id).revisions.map(&:class)).to eq([revision_class])
        expect(model.includes(:revisions).find(record.id).revisions.map(&:class)).to eq([revision_class])
      end
    end

    it 'loads the item and the user through the inherited associations' do
      user = User.create!(name: 'Igor')
      described_class.info = {user_id: user.id}
      record = observed_model.create!(name: 'Facebook', identifier: 'FB')

      revision = revision_class.find(record.revisions.first.id)
      aggregate_failures do
        expect(revision.item).to eq(record)
        expect(revision.user).to eq(user)
        expect(revision_class.includes(:user, :item).find(revision.id).user).to eq(user)
      end
    end

    it 'declares a user association of its own, leaving Recorder::Revision alone' do
      account = stub_const('Account', Class.new(ApplicationRecord) { self.table_name = 'users' })
      revision_class.belongs_to :user, class_name: 'Account', optional: true
      described_class.info = {user_id: User.create!(name: 'Igor').id}
      create_security

      aggregate_failures do
        expect(revision_class.last.user).to be_an_instance_of(account)
        expect(Recorder::Revision.last.user).to be_an_instance_of(User)
      end
    end

    it 'sets the item of the revisions has_many loads, without a query' do
      record = observed_model.create!(name: 'Facebook', identifier: 'FB')
      revision = record.class.find(record.id).revisions.first

      expect(revision.association(:item)).to be_loaded
    end
  end

  describe 'when the setting is read' do
    it 'resolves a name assigned before its class is defined' do
      described_class.config.revision_class = 'LateRevision'
      model = observed_model
      revision_class = define_revision_class('LateRevision')

      record = model.create!(name: 'Facebook', identifier: 'FB')

      aggregate_failures do
        expect(created.map(&:class)).to eq([revision_class])
        expect(record.revisions.reload.map(&:class)).to eq([revision_class])
      end
    end

    # A model declares `revisions` when it loads, so one loaded before the
    # assignment keeps the class that was set then. The revisions it writes go
    # through the class set now.
    it 'keeps has_many :revisions of a model loaded before the assignment on the class set then' do
      early = observed_model('EarlyLedger')
      revision_class = define_revision_class
      described_class.config.revision_class = 'AppRevision'
      late = observed_model('LateLedger')

      early_record = early.create!(name: 'Facebook', identifier: 'FB')
      late_record = late.create!(name: 'Alphabet', identifier: 'GOOG')

      aggregate_failures do
        expect(created.map(&:class)).to eq([revision_class, revision_class])
        expect(early_record.revisions.reload.map(&:class)).to eq([Recorder::Revision])
        expect(late_record.revisions.reload.map(&:class)).to eq([revision_class])
      end
    end

    # Zeitwerk replaces the constant with a new class on reload, and the
    # models with it.
    it 'picks up a class that was reloaded, and never the one it replaced' do
      described_class.config.revision_class = 'AppRevision'
      stale = define_revision_class
      create_security

      reloaded = define_revision_class
      record = observed_model.create!(name: 'Alphabet', identifier: 'GOOG')
      create_security

      aggregate_failures do
        expect(described_class.revision_class).to equal(reloaded)
        expect(created.map(&:class)).to eq([stale, reloaded, reloaded])
        expect(record.revisions.reload.map(&:class)).to eq([reloaded])
      end
    end
  end

  describe 'a name that does not resolve to a revision class' do
    {
      'a class that is not defined' => 'MissingRevision',
      'a class that is not a model' => 'String',
      'a model that is not a revision' => 'User'
    }.each do |description, name|
      it "fails the save for #{description}, naming the setting" do
        described_class.config.revision_class = name

        expect { create_security }.to raise_error(
          ArgumentError, "Recorder.config.revision_class must name Recorder::Revision or a subclass of it, got #{name.inspect}"
        )
        expect(Security.where(identifier: 'FB')).not_to exist
      end
    end

    context 'when Active Record would treat the class as single-table inheritance' do
      # A copy of recorder_revisions with a `type` column, which only this
      # example sees.
      before do
        ActiveRecord::Base.connection.execute(<<~SQL)
          CREATE TEMPORARY TABLE typed_revisions (LIKE recorder_revisions INCLUDING ALL, type varchar)
        SQL
        described_class.config.revision_class = 'AppRevision'
      end

      it 'fails the save, saying how to turn it off' do
        define_revision_class { self.table_name = 'typed_revisions' }

        expect { create_security }.to raise_error(
          ArgumentError, /AppRevision would store its name in the `type` column of typed_revisions.*inheritance_column = nil/
        )
        expect(Security.where(identifier: 'FB')).not_to exist
      end

      it 'accepts the class once inheritance is off' do
        revision_class =
          define_revision_class do
            self.table_name = 'typed_revisions'
            self.inheritance_column = nil
          end

        create_security

        expect(revision_class.pluck(:type)).to eq([nil])
      end
    end
  end

  describe 'callbacks of the class' do
    before { described_class.config.revision_class = 'AppRevision' }

    it 'run in the save transaction, so a save that rolls back leaves no revision' do
      define_revision_class

      expect { roll_back { create_security } }.not_to change(Recorder::Revision, :count)
      expect(created.size).to eq(1)
    end

    it 'run an after_commit callback once the save commits, and not for a save that rolls back' do
      committed = []
      define_revision_class { after_create_commit { committed << event } }

      roll_back { create_security }
      ActiveRecord::Base.transaction(requires_new: true) do
        Security.create!(name: 'Alphabet', identifier: 'GOOG')
        expect(committed).to be_empty
      end

      expect(committed).to eq(%w[create])
    end

    it 'fail the save with Recorder::RevisionNotSaved when one halts' do
      define_revision_class { before_create { throw :abort } }

      expect { create_security }.to raise_error(Recorder::RevisionNotSaved) do |error|
        expect(error.record).to be_an_instance_of(AppRevision)
      end
      expect(Security.where(identifier: 'FB')).not_to exist
    end

    it 'fail the save with Recorder::RevisionNotSaved when a validation of the class fails' do
      define_revision_class { validates :user_id, presence: true }

      expect { create_security }.to raise_error(Recorder::RevisionNotSaved, /User can't be blank/)
      expect(Security.where(identifier: 'FB')).not_to exist
    end

    it 'fail the save with the error one raises' do
      define_revision_class { after_create { raise 'feed is down' } }

      expect { create_security }.to raise_error(RuntimeError, 'feed is down')
      expect(Security.where(identifier: 'FB')).not_to exist
    end

    it 'leave the save alone when one rescues its own error' do
      define_revision_class do
        after_create do
          raise 'feed is down'
        rescue RuntimeError
          nil
        end
      end

      expect { create_security }.to change(AppRevision, :count).by(1)
    end
  end

  describe 'the table' do
    let!(:revision_class) { define_revision_class }
    let(:security) { create_security }

    before do
      security.update!(name: 'Meta')
      described_class.config.revision_class = 'AppRevision'
      security.update!(name: 'Facebook')
    end

    it 'is queried without a type condition' do
      aggregate_failures do
        expect(revision_class.descends_from_active_record?).to be(true)
        expect(revision_class.where(item: security).to_sql).not_to include('"type"')
        expect(revision_class.table_name).to eq('recorder_revisions')
      end
    end

    it 'returns the same rows through Recorder::Revision and through the class' do
      ids = Recorder::Revision.where(item: security).order(:id).pluck(:id)

      aggregate_failures do
        expect(ids.size).to eq(3)
        expect(revision_class.where(item: security).order(:id).pluck(:id)).to eq(ids)
        expect(revision_class.count).to eq(Recorder::Revision.count)
        expect(revision_class.find(ids.first)).to be_an_instance_of(revision_class)
        expect(Recorder::Revision.find(ids.last)).to be_an_instance_of(Recorder::Revision)
      end
    end

    it 'never stores the name of the class' do
      rows = ActiveRecord::Base.connection.select_rows('SELECT * FROM recorder_revisions')

      aggregate_failures do
        expect(rows.size).to eq(3)
        expect(rows.flatten.compact.join(' ')).not_to include('AppRevision')
        expect(Recorder::Revision.distinct.pluck(:item_type)).to eq(['Security'])
      end
    end
  end

  describe 'reading revisions through the class' do
    let!(:revision_class) { define_revision_class }

    before { described_class.config.revision_class = 'AppRevision' }

    def both(revision)
      [Recorder::Revision.find(revision.id), revision_class.find(revision.id)]
    end

    it 'builds the same item changeset as Recorder::Revision' do
      security = create_security
      security.update!(name: 'Meta')

      changesets = both(revision_class.last).map(&:item_changeset)
      expect(changesets.map { |changeset| [changeset.class, changeset.previous(:name), changeset.next(:name)] })
        .to eq([[Recorder::Changeset, 'Facebook', 'Meta']] * 2)
    end

    it 'reads association changes as Recorder::Revision does' do
      guard = Instrument.create!(name: 'Meta', identifier: 'META')
      instrument = Instrument.create!(name: 'Instagram', identifier: 'IG', guard: guard)
      revision = revision_class.create!(
        item: instrument, event: 'update', action_date: Date.current,
        data: {attributes: {name: 'Instagram'}, associations: {guard: {changes: {name: %w[Facebook Meta]}}}}
      )

      readers =
        both(revision).map do |read|
          [read.changed_associations, read.association_changeset('guard').next(:name)]
        end
      expect(readers).to eq([[['guard'], 'Meta']] * 2)
    end

    it 'orders them as Recorder::Revision does' do
      security = create_security
      security.update!(name: 'Meta')
      revision_class.where(event: 'create').update_all(created_at: 1.day.ago)

      expect(revision_class.where(item: security).ordered_by_created_at.pluck(:event)).to eq(%w[update create])
    end

    # A Draper decorator answers `decorated?` and holds the model as `source`.
    it 'resolves the changeset class of a decorated item' do
      stub_const('Draper', Module.new)
      changeset_class = stub_const('SecurityChangeset', Class.new(Recorder::Changeset))
      decorated = Struct.new(:source) { def decorated? = true }
      security = create_security
      security.update!(name: 'Meta')
      revision = revision_class.last
      allow(revision).to receive(:item).and_return(decorated.new(security))

      expect(revision.item_changeset).to be_an_instance_of(changeset_class)
    end
  end
end
