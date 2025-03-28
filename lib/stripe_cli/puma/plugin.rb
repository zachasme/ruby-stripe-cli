begin
  require "puma"
  require "stripe"
  require_relative "plugin/stripe"
rescue LoadError
  # handle lack of library or just leave it be
end
