class Security < ActiveRecord::Base
  include ::Recorder::Observer
end
