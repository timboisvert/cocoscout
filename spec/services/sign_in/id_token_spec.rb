# frozen_string_literal: true

require "rails_helper"

RSpec.describe SignIn::IdToken do
  let(:key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:jwk) { JWT::JWK.new(key, kid: "test-kid") }
  let(:claims) do
    { "iss" => "https://accounts.google.com", "aud" => "google-client", "sub" => "g-123", "email" => "maya@example.com",
      "email_verified" => true, "nonce" => "n-1", "exp" => 5.minutes.from_now.to_i, "iat" => Time.current.to_i }
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("GOOGLE_SIGNIN_CLIENT_ID").and_return("google-client")
    allow_any_instance_of(described_class).to receive(:fetch_keys).and_return({ "keys" => [ jwk.export ] })
  end

  def token(overrides = {}, signing_key: key)
    JWT.encode(claims.merge(overrides), signing_key, "RS256", { kid: "test-kid" })
  end

  it "returns the claims of a token Google signed for us, with this sign-in's nonce" do
    expect(described_class.verify("google", token, nonce: "n-1")).to include("sub" => "g-123", "email" => "maya@example.com")
  end

  it "refuses another app's token, a wrong nonce, an expired one, and a forged one" do
    expect { described_class.verify("google", token({ "aud" => "someone-else" }), nonce: "n-1") }.to raise_error(described_class::Invalid)
    expect { described_class.verify("google", token, nonce: "other") }.to raise_error(described_class::Invalid)
    expect { described_class.verify("google", token({ "exp" => 10.minutes.ago.to_i }), nonce: "n-1") }.to raise_error(described_class::Invalid)
    expect { described_class.verify("google", token({}, signing_key: OpenSSL::PKey::RSA.generate(2048)), nonce: "n-1") }.to raise_error(described_class::Invalid)
  end

  it "reads the Apple key whether its line breaks arrived as breaks, \\n, or spaces" do
    pem = OpenSSL::PKey::EC.generate("prime256v1").private_to_pem
    [ pem, pem.gsub("\n", "\\n"), pem.gsub("\n", " ") ].each do |form|
      allow(ENV).to receive(:[]).with("APPLE_PRIVATE_KEY").and_return(form)
      expect(SignIn::Providers.apple_private_key).to be_a(OpenSSL::PKey::EC)
    end
  end
end
