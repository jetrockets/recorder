# frozen_string_literal: true

require 'rails_helper'

# The concern is included inside `controller` blocks, where `described_class`
# is not defined.
# rubocop:disable RSpec/DescribedClass
RSpec.describe Recorder::Rails::ControllerConcern, type: :controller do
  controller(ActionController::Base) do
    include Recorder::Rails::ControllerConcern

    def index
      head :ok
    end
  end

  before { routes.draw { get 'index' => 'anonymous#index' } }

  it 'keeps the request context before the action runs' do
    get :index

    expect(Recorder.store.params).to include(ip: '0.0.0.0', action_date: Date.current, user_id: nil, meta: nil)
  end

  it 'leaves the user blank when the controller has no current_user' do
    get :index

    expect(Recorder.store.params[:user_id]).to be_nil
  end

  context 'when current_user returns a record' do
    controller(ActionController::Base) do
      include Recorder::Rails::ControllerConcern

      def index
        head :ok
      end

      private

      def current_user
        User.new(id: 7)
      end
    end

    it 'keeps its id' do
      get :index

      expect(Recorder.store.params[:user_id]).to eq(7)
    end
  end

  context 'when current_user returns the id itself' do
    controller(ActionController::Base) do
      include Recorder::Rails::ControllerConcern

      def index
        head :ok
      end

      private

      def current_user
        42
      end
    end

    it 'keeps it as it is' do
      get :index

      expect(Recorder.store.params[:user_id]).to eq(42)
    end
  end

  context 'when the controller overrides recorder_meta' do
    controller(ActionController::Base) do
      include Recorder::Rails::ControllerConcern

      def index
        head :ok
      end

      private

      def recorder_meta
        {locale: 'en'}
      end
    end

    it 'keeps it in the request context' do
      get :index

      expect(Recorder.store.params[:meta]).to eq(locale: 'en')
    end

    it 'calls it once per request' do
      allow(controller).to receive(:recorder_meta).and_call_original

      get :index

      expect(controller).to have_received(:recorder_meta).once
    end

    it 'writes it on the revisions that follow' do
      get :index
      security = Security.create!(name: 'Facebook', identifier: 'FB')

      expect(security.revisions.last.meta).to eq('locale' => 'en')
    end
  end

  context 'when the controller moves set_recorder_info after its own before_action' do
    controller(ActionController::Base) do
      include Recorder::Rails::ControllerConcern

      before_action :set_tenant
      skip_before_action :set_recorder_info
      before_action :set_recorder_info

      def index
        head :ok
      end

      private

      attr_reader :tenant

      def set_tenant
        @tenant = 'acme'
      end

      def recorder_meta
        {tenant: tenant}
      end
    end

    it 'still computes meta where set_recorder_meta runs' do
      get :index

      expect(Recorder.store.params[:meta]).to eq(tenant: nil)
    end
  end

  context 'when recorder_meta returns a Proc' do
    controller(ActionController::Base) do
      include Recorder::Rails::ControllerConcern

      def index
        head :ok
      end

      def create
        Security.create!(name: 'Facebook', identifier: 'FB').update!(name: 'Meta')
        head :created
      end

      def tape
        Recorder::Tape.record(item_type: 'Security', item_id: 1, event: 'create', data: {attributes: {name: 'Facebook'}})
        head :created
      end

      private

      def recorder_meta
        -> { costly_meta }
      end

      def costly_meta
        {locale: 'en'}
      end
    end

    before do
      routes.draw do
        get 'index' => 'anonymous#index'
        post 'create' => 'anonymous#create'
        post 'tape' => 'anonymous#tape'
      end
      allow(controller).to receive(:costly_meta).and_call_original
    end

    it 'does not call it on a request that writes no revision' do
      get :index

      expect(controller).not_to have_received(:costly_meta)
    end

    it 'calls it once on a request that writes several revisions, which all carry its value' do
      post :create

      expect(controller).to have_received(:costly_meta).once
      expect(Recorder::Revision.pluck(:meta)).to eq([{'locale' => 'en'}] * 2)
    end

    it 'writes its value on a revision written through Tape' do
      post :tape

      expect(Recorder::Revision.last.meta).to eq('locale' => 'en')
    end
  end

  context 'when the action changes state before its first revision' do
    controller(ActionController::Base) do
      include Recorder::Rails::ControllerConcern

      def create
        @current_user = User.create!(name: 'Ann')
        Security.create!(name: 'Facebook', identifier: 'FB')
        head :created
      end

      private

      attr_reader :current_user

      # Reads the user before the action, and again inside the Proc.
      def recorder_meta
        before_action = current_user&.id
        -> { {before_action: before_action, first_revision: current_user&.id} }
      end
    end

    before { routes.draw { post 'create' => 'anonymous#create' } }

    it 'sees it inside the Proc only' do
      post :create
      revision = Recorder::Revision.last

      expect(revision.meta).to eq('before_action' => nil, 'first_revision' => User.last.id)
      expect(revision.user_id).to be_nil
    end
  end

  context 'when the Proc recorder_meta returns raises' do
    controller(ActionController::Base) do
      include Recorder::Rails::ControllerConcern

      def create
        User.create!(name: 'Ann')
        Security.create!(name: 'Facebook', identifier: 'FB')
        head :created
      end

      private

      def recorder_meta
        -> { raise KeyError, 'no meta' }
      end
    end

    before { routes.draw { post 'create' => 'anonymous#create' } }

    it 'fails the save that writes the first revision, after the action has run up to it' do
      expect { post :create }.to raise_error(KeyError, 'no meta')
      expect(Security.where(identifier: 'FB')).not_to exist
      expect(User.where(name: 'Ann')).to exist
    end
  end

  context 'when the controller skips set_recorder_meta' do
    controller(ActionController::Base) do
      include Recorder::Rails::ControllerConcern

      skip_before_action :set_recorder_meta

      def index
        head :ok
      end

      private

      def recorder_meta
        {locale: 'en'}
      end
    end

    it 'leaves meta unset' do
      allow(controller).to receive(:recorder_meta).and_call_original

      get :index

      expect(controller).not_to have_received(:recorder_meta)
      expect(Recorder.store.params[:meta]).to be_nil
    end

    it 'writes no meta on the revisions that follow' do
      get :index
      security = Security.create!(name: 'Facebook', identifier: 'FB')

      expect(security.revisions.last.meta).to be_nil
    end

    it 'still keeps the rest of the request context' do
      get :index

      expect(Recorder.store.params).to include(ip: '0.0.0.0', action_date: Date.current, user_id: nil)
    end
  end
end
# rubocop:enable RSpec/DescribedClass
