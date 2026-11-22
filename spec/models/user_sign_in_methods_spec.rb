# frozen_string_literal: true

require "rails_helper"

# The sign-in plan's groundwork on User (2026-11-22): who chose a password,
# who has claimed their account, and accounts made with no chosen password.
RSpec.describe User do
  describe "password_set_at" do
    it "is stamped when a person chooses a password" do
      user = described_class.create!(email_address: "chose@example.com", password: "Password123!")
      expect(user.password_chosen?).to be(true)
    end

    it "stays empty for an account nobody chose a password for, which still has a valid one" do
      user = described_class.create_unclaimed!(email_address: "added@example.com")

      expect(user.password_chosen?).to be(false)
      expect(user.password_digest).to be_present
      expect(user.reload.password_set_at).to be_nil
    end

    it "is stamped when that person later chooses one, and cleared when it is forgotten" do
      user = described_class.create_unclaimed!(email_address: "added@example.com")

      user.update!(password: "Password123!")
      expect(user.reload.password_chosen?).to be(true)
      expect(user.authenticate("Password123!")).to be_truthy

      user.forget_password!
      expect(user.reload.password_chosen?).to be(false)
      expect(user.authenticate("Password123!")).to be(false)
    end
  end

  describe "#claimed?" do
    it "is false until the person has been seen or has proved their address" do
      user = described_class.create_unclaimed!(email_address: "added@example.com")
      expect(user.claimed?).to be(false)

      user.update!(email_verified_at: Time.current)
      expect(user.claimed?).to be(true)
      expect(described_class.new(last_seen_at: 1.day.ago).claimed?).to be(true)
    end
  end

  # A random password must also record that nobody chose it, so everything
  # goes through create_unclaimed! / forget_password!. Mics code is left as it
  # is (Tim, 2026-10-16), so its two callers are allowed.
  it "is the only place that makes a random password" do
    allowed = %w[app/models/user.rb app/controllers/mics/owner_controller.rb app/controllers/superadmin/mics/hubs_controller.rb]
    callers = Dir[Rails.root.join("{app,lib}/**/*.rb")].select { |f| File.read(f).include?("generate_secure_password") }
                                                      .map { |f| Pathname(f).relative_path_from(Rails.root).to_s }

    expect(callers - allowed).to eq([])
  end
end
