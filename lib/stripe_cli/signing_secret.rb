# frozen_string_literal: true

module StripeCLI
  def self.signing_secret(api_key)
    secret = `#{executable} listen --api-key "#{api_key}" --print-secret`.chomp
    return nil unless $?.success?
    secret unless secret.empty?
  rescue
    nil
  end
end
