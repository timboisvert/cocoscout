# frozen_string_literal: true

# Seeding the dev database from production (Tim, 2026-11-01). bin/seed_dev_from_prod
# runs these around the restore; see the top of that script for the flow.
namespace :dev_seed do
  KEPT_LOGINS = Rails.root.join("tmp/dev_seed/kept_logins.json")

  def dev_seed_keep_emails
    ENV.fetch("KEEP_EMAILS", "boisvert@gmail.com,dev-manager@cocoscout.test").split(",").map { |e| e.strip.downcase }.compact_blank
  end

  def dev_seed_guard!
    abort "dev_seed runs in development only" unless Rails.env.development?
  end

  desc "Remember the kept dev logins (password, name, organization roles by organization name) before the dev database is replaced"
  task remember_logins: :environment do
    dev_seed_guard!
    logins = User.where("lower(email_address) IN (?)", dev_seed_keep_emails).map do |user|
      { email: user.email_address.downcase, password_digest: user.password_digest, name: user.default_person&.name || user.email_address,
        roles: OrganizationRole.where(user: user).includes(:organization).map { |r| { organization: r.organization&.name, company_role: r.company_role } } }
    end
    FileUtils.mkdir_p(KEPT_LOGINS.dirname)
    File.write(KEPT_LOGINS, JSON.pretty_generate(logins))
    File.chmod(0o600, KEPT_LOGINS)
    puts "Remembered #{logins.map { |l| l[:email] }.join(', ').presence || 'no logins'}."
  end

  desc "Put the kept dev logins back: same password as before; a login production doesn't have is made again, with its roles on organizations of the same name"
  task restore_logins: :environment do
    dev_seed_guard!
    abort "Nothing remembered at #{KEPT_LOGINS}" unless File.exist?(KEPT_LOGINS)

    JSON.parse(File.read(KEPT_LOGINS)).each do |login|
      user = User.where("lower(email_address) = ?", login["email"]).first
      made = user.nil?
      user ||= User.new(email_address: login["email"], password: SecureRandom.hex(16))
      user.save!(validate: false)
      user.update_columns(password_digest: login["password_digest"])
      Person.create!(user: user, name: login["name"], email: login["email"]) if user.people.none?
      if made
        Array(login["roles"]).each do |role|
          org = Organization.find_by(name: role["organization"])
          next unless org

          OrganizationRole.find_or_create_by!(user: user, organization: org) { |r| r.company_role = role["company_role"] }
        end
      end
      puts "  #{login['email']}: #{made ? 'made again' : 'kept'}, dev password as before"
    end
    File.delete(KEPT_LOGINS)
  end

  desc "Scrub production's data in the dev database: only the kept logins work, nobody else can be reached"
  task scrub: :environment do
    dev_seed_guard!
    copied_on = ENV["SEEDED_ON"].present? ? Date.parse(ENV["SEEDED_ON"]) : Date.current
    report = Dev::ProdCopyScrubber.new(keep_emails: dev_seed_keep_emails, copied_on: copied_on).run!
    report.sort.each { |what, count| puts format("  %-60s %d", what, count) }
  end

  desc "Copy production's images into the dev bucket (no documents, W-9s or email logs); safe to run again, it skips what's there"
  task files: :environment do
    dev_seed_guard!
    service = ActiveStorage::Blob.service
    abort "Dev doesn't store files in S3 (#{service.class.name}); nothing to copy." unless service.respond_to?(:bucket)

    from = ENV.fetch("PROD_BUCKET", "cocoscout-production")
    Dev::BlobCopier.new(client: service.client.client, from: from, to: service.bucket.name, keys: Dev::BlobCopier.keys).run!
  rescue Dev::BlobCopier::AccessDenied => e
    abort e.message
  end
end
