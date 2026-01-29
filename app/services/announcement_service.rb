# frozen_string_literal: true

# Service for loading and filtering announcements from YAML config
#
# Usage:
#   AnnouncementService.announcements_for(user)
#
# Targeting options (set in YAML):
#   - all: Show to all users (default)
#   - superadmin: Superadmins only (for testing unreleased features)
#   - no_sms: Users who haven't set up SMS
#   - has_sms: Users who have SMS enabled
#   - no_phone: Users without a phone number
#   - has_phone: Users with a phone number
#
class AnnouncementService
  class << self
    def announcements_for(user)
      return [] unless user

      all_announcements.select do |announcement|
        !user.announcement_dismissed?(announcement[:id]) &&
          announcement_active?(announcement) &&
          user_matches_targeting?(user, announcement)
      end
    end

    def all_announcements
      @all_announcements ||= load_announcements
    end

    def reload!
      @all_announcements = nil
    end

    private

    def load_announcements
      config_path = Rails.root.join("config", "announcements.yml")
      return [] unless File.exist?(config_path)

      config = YAML.safe_load_file(config_path, symbolize_names: true)
      config[:announcements] || []
    rescue StandardError => e
      Rails.logger.error("Failed to load announcements: #{e.message}")
      []
    end

    def announcement_active?(announcement)
      now = Time.current

      # Check start_date
      if announcement[:start_date]
        start_time = Time.zone.parse(announcement[:start_date].to_s)
        return false if now < start_time
      end

      # Check end_date
      if announcement[:end_date]
        end_time = Time.zone.parse(announcement[:end_date].to_s)
        return false if now > end_time
      end

      true
    end

    def user_matches_targeting?(user, announcement)
      targeting = announcement[:targeting]
      return true if targeting.nil? || targeting.to_s == "all"

      case targeting.to_s
      when "superadmin"
        user.superadmin?
      when "no_sms"
        !user.sms_enabled?
      when "has_sms"
        user.sms_enabled?
      when "no_phone"
        user.sms_phone.blank?
      when "has_phone"
        user.sms_phone.present?
      else
        true
      end
    end
  end
end
