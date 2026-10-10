# frozen_string_literal: true

# Test accounts for driving the iOS app in the Simulator against this Mac's
# development server, one per kind of person the app serves. Development only;
# safe to run again.
#
#   bin/rails ios:dev_users
#   bin/rails ios:dev_users ORG_ID=5
namespace :ios do
  DEV_PASSWORD = "CocoIos-dev-1!"

  desc "Create the iOS Simulator test accounts (development only)"
  task dev_users: :environment do
    abort "ios:dev_users only runs in development." unless Rails.env.development?

    org = ENV["ORG_ID"].present? ? Organization.find(ENV["ORG_ID"]) : Organization.joins(:ticketing_profile).find_by!(ticketing_profiles: { enabled: true })
    production = org.productions.joins(:shows).where("shows.date_and_time > ?", Time.current).first || org.productions.first

    account = lambda do |email, name|
      user = User.find_or_initialize_by(email_address: email)
      user.password = DEV_PASSWORD
      user.save!
      person = user.people.first || Person.create!(user: user, name: name, email: email)
      user.update!(default_person: person)
      person.organizations << org unless person.organizations.include?(org)
      [ user, person ]
    end

    in_pool = lambda do |person|
      pool = production.effective_talent_pool
      pool.talent_pool_memberships.find_or_create_by!(member: person)
    end

    # A performer in the production's talent pool: Home, Tasks, Shows, Messages.
    _, performer = account.call("ios-performer@cocoscout.test", "Ida Performer")
    in_pool.call(performer)

    # House staff only: My Shifts and Work Availability.
    _, staffer = account.call("ios-staff@cocoscout.test", "Sam Staff")
    org.organization_staff_members.find_or_create_by!(person: staffer) { |m| m.onboarding_state = "completed" }

    # Works the door (box office), and performs too: everything at once.
    door_user, door_person = account.call("ios-door@cocoscout.test", "Dee Door")
    in_pool.call(door_person)
    unless org.ticketing_access_grants.active.exists?(user: door_user)
      org.ticketing_access_grants.create!(user: door_user, access_level: "box_office")
    end

    puts "#{org.name} (#{production.name}): ios-performer@, ios-staff@, ios-door@cocoscout.test — password in lib/tasks/ios_dev.rake"
  end
end
