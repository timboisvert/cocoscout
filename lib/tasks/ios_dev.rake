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

  # A party of three comp tickets on the next show the door account can work,
  # for trying the app's scanner. Each run puts them back to not checked in
  # and prints their codes (type one into the Simulator's scanner, which has
  # no camera). Comps carry no money, so nothing reaches the books.
  #
  #   bin/rails ios:door_tickets
  #   bin/rails ios:door_tickets LISTING_ID=16
  desc "Make or reset scannable test tickets for the iOS door scanner (development only)"
  task door_tickets: :environment do
    abort "ios:door_tickets only runs in development." unless Rails.env.development?

    door_user = User.find_by!(email_address: "ios-door@cocoscout.test")
    org = TicketingAccessGrant.active.where(user: door_user).first!.organization
    listing = if ENV["LISTING_ID"].present?
      org.ticket_listings.find(ENV["LISTING_ID"])
    else
      org.ticket_listings.joins(:show).where(status: "on_sale").where("shows.date_and_time > ?", 1.day.ago).order("shows.date_and_time").first!
    end
    tier = listing.ticket_tiers.active.first!

    order = listing.ticket_orders.find_by(buyer_name: "Scan Test Party") ||
            TicketOrder.create!(organization: org, ticket_listing: listing, status: "paid", paid_at: Time.current, channel: "comp",
                                money_path: "none", fee_mode: listing.effective_fee_mode, buyer_name: "Scan Test Party")
    (3 - order.tickets.count).times do
      order.tickets.create!(ticket_tier: tier, ticket_listing: listing, status: "valid", price_cents: tier.price_cents, discount_cents: tier.price_cents)
    end
    order.tickets.update_all(status: "valid", checked_in_at: nil, checked_in_by_id: nil, updated_at: Time.current)

    # A bottle to hand over, when the organization sells any, so the
    # scanner's Delivered button has something to deliver.
    if (product = org.ticket_products.first)
      item = order.ticket_order_items.find_or_initialize_by(ticket_product: product)
      item.update!(organization: org, ticket_listing: listing, status: "valid", name: product.name, unit_price_cents: 0, quantity: 1)
      item.update_columns(fulfilled_quantity: 0, fulfilled_at: nil, fulfilled_by_id: nil)
    end

    puts "#{listing.display_title}, #{listing.show.date_and_time.strftime('%a %b %-d %-l:%M %p')} (listing #{listing.id}, order #{order.code})"
    order.tickets.order(:id).each { |ticket| puts "  #{ticket.code}" }
  end
end
