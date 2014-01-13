$LOAD_PATH.unshift File.expand_path(File.dirname(__FILE__) + '/../lib/')

require 'lookout_rack_utils'

require 'rspec'

require 'rack/test'

Dir["./spec/support/**/*.rb"].sort.each do |f|
  require f
end

RSpec.configure do |c|
  c.include(Rack::Test::Methods, :type => :route)
  c.include(RouteHelpers, :type => :route)
end
