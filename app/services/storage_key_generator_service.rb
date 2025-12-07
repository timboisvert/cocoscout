# frozen_string_literal: true

# Generates hierarchical S3 keys based on attachment ownership.
#
# Key structure examples:
#   - people/{person_id}/headshots/{blob_key}
#   - people/{person_id}/resumes/{blob_key}
#   - groups/{group_id}/headshots/{blob_key}
#   - organizations/{org_id}/productions/{prod_id}/posters/{blob_key}
#   - organizations/{org_id}/productions/{prod_id}/shows/{show_id}/posters/{blob_key}
#   - action_text/{record_type}/{record_id}/{blob_key}
#
# People and Groups are first-class citizens (not nested under organizations).
#
class StorageKeyGeneratorService
  class << self
    # Generate a hierarchical key for a blob based on its attachment.
    # Returns nil if no key can be generated (e.g., orphaned blob).
    def generate_key_for_blob(blob)
      attachment = blob.attachments.first
      return nil unless attachment

      generate_key_for_attachment(attachment, blob)
    end

    # Generate a hierarchical key for an attachment.
    def generate_key_for_attachment(attachment, blob = nil)
      blob ||= attachment.blob
      record = attachment.record
      attachment_name = attachment.name

      return nil unless record

      key = build_key_for_record(record, attachment_name, blob.key)
      key || fallback_key(attachment, blob)
    end

    private

    def build_key_for_record(record, attachment_name, blob_key)
      case record
      when ProfileHeadshot
        build_profile_headshot_key(record, blob_key)
      when ProfileResume
        build_profile_resume_key(record, blob_key)
      when Poster
        build_poster_key(record, blob_key)
      when Show
        build_show_attachment_key(record, attachment_name, blob_key)
      when ActionText::RichText
        build_action_text_key(record, blob_key)
      else
        # Generic fallback for other record types
        build_generic_key(record, attachment_name, blob_key)
      end
    end

    def build_profile_headshot_key(profile_headshot, blob_key)
      profileable = profile_headshot.profileable

      case profileable
      when Person
        "people/#{profileable.id}/headshots/#{blob_key}"
      when Group
        "groups/#{profileable.id}/headshots/#{blob_key}"
      end
    end

    def build_profile_resume_key(profile_resume, blob_key)
      profileable = profile_resume.profileable

      case profileable
      when Person
        "people/#{profileable.id}/resumes/#{blob_key}"
      when Group
        "groups/#{profileable.id}/resumes/#{blob_key}"
      end
    end

    def build_poster_key(poster, blob_key)
      production = poster.production
      return nil unless production

      org_id = production.organization_id
      "organizations/#{org_id}/productions/#{production.id}/posters/#{blob_key}"
    end

    def build_show_attachment_key(show, attachment_name, blob_key)
      production = show.production
      return nil unless production

      org_id = production.organization_id
      folder = attachment_name.to_s.pluralize # "poster" -> "posters"
      "organizations/#{org_id}/productions/#{production.id}/shows/#{show.id}/#{folder}/#{blob_key}"
    end

    def build_action_text_key(rich_text, blob_key)
      record_type = rich_text.record_type.underscore.pluralize
      record_id = rich_text.record_id
      "action_text/#{record_type}/#{record_id}/#{blob_key}"
    end

    def build_generic_key(record, attachment_name, blob_key)
      record_type = record.class.name.underscore.pluralize
      record_id = record.id

      # Normalize attachment name (e.g., "photo" -> "photos")
      folder_name = attachment_name.to_s.pluralize

      "#{record_type}/#{record_id}/#{folder_name}/#{blob_key}"
    end

    def fallback_key(attachment, blob)
      # If we can't determine the proper path, use a generic structure
      record_type = attachment.record_type.underscore.pluralize
      record_id = attachment.record_id
      attachment_name = attachment.name.to_s.pluralize

      "#{record_type}/#{record_id}/#{attachment_name}/#{blob.key}"
    end
  end
end
