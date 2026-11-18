# frozen_string_literal: true

# Which clock a piece of work reads in. Every organization has a time zone
# (Organization#time_zone; Central unless it picked another). A request for
# an organization's pages runs in it (ApplicationController#use_time_zone_of),
# and so do jobs and mailers whose arguments name the organization
# (ApplicationJob, ApplicationMailer): a show at 7:00 PM in Los Angeles is
# entered, shown, emailed and pushed as 7:00 PM.
module TimeZones
  module_function

  def default = Rails.application.config.time_zone

  # The zone of the first thing that knows one: an Organization, something
  # with an organization (a shift, a production, a listing, an order), a show
  # (through its production), a hash with an organization_id, or a
  # GlobalID-serialized record. Nil when nothing does.
  def of(*things)
    things.flatten.each do |thing|
      zone = zone_of(thing)
      return zone if zone
    end
    nil
  end

  def zone_of(thing)
    case thing
    when nil then nil
    when Organization then thing.time_zone.presence
    when Hash
      id = thing[:organization_id] || thing["organization_id"]
      org = id && Organization.find_by(id: id)
      org&.time_zone.presence || of(*thing.values.select { |v| v.is_a?(ActiveRecord::Base) })
    when ActiveRecord::Base
      if thing.respond_to?(:organization) && thing.organization.is_a?(Organization)
        thing.organization.time_zone.presence
      elsif thing.respond_to?(:production) && thing.production.respond_to?(:organization)
        thing.production.organization&.time_zone.presence
      elsif thing.respond_to?(:shift) && thing.shift.respond_to?(:organization)
        thing.shift.organization&.time_zone.presence
      end
    end
  rescue StandardError
    nil
  end

  # Run a block in a zone, or in the current one when none is known.
  def use(zone, &block)
    zone.present? ? Time.use_zone(zone, &block) : yield
  end

  # The zones an organization can pick: the US ones first, then the rest.
  def choices
    us = ActiveSupport::TimeZone.us_zones
    us + (ActiveSupport::TimeZone.all - us)
  end
end
