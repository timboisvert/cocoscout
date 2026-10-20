# frozen_string_literal: true

# Whether a manager changed the words of a notice before sending it (V1.1
# plan §9, option 3, Tim 2026-10-20): a notice is always a Notification, and
# also a Message from the manager when they changed its words or added a
# note. Compares plain text, so spacing, markup and the editor's own HTML
# never count as a change.
#
#   ManagerWords.changed?([sent_subject, default_subject], [sent_body, default_body])
#   ManagerWords.note?(note)
module ManagerWords
  module_function

  # Each pair is [what was sent, the default it started from]. A pair whose
  # sent side is blank wasn't touched.
  def changed?(*pairs)
    pairs.any? do |sent, default|
      next false if plain(sent).blank?

      plain(sent) != plain(default)
    end
  end

  def note?(note) = plain(note).present?

  def plain(text)
    html = text.respond_to?(:to_html) ? text.to_html : text.to_s
    CGI.unescapeHTML(ActionController::Base.helpers.strip_tags(html.gsub(/<br\s*\/?>|<\/(p|div|li|h\d)>/i, " "))).squish
  end
end
