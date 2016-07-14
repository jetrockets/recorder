class Thing < ActiveRecord::Base
  include ::Recorder::Observer
end
