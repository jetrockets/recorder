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

    it 'writes it on the revisions that follow' do
      get :index
      security = Security.create!(name: 'Facebook', identifier: 'FB')

      expect(security.revisions.last.meta).to eq('locale' => 'en')
    end
  end
end
# rubocop:enable RSpec/DescribedClass
