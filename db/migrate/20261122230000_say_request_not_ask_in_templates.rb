# frozen_string_literal: true

# The word is request, never ask (Tim's copy rule, 2026-11-20; swept across
# the app 2026-11-22). Swaps only these phrases in the stored templates, so
# any other words an organization or superadmin changed stay as they are.
class SayRequestNotAskInTemplates < ActiveRecord::Migration[8.1]
  class Template < ActiveRecord::Base
    self.table_name = "content_templates"
  end

  PHRASES = {
    "payout_returned_manager" => [ [ "We've asked them to check.", "We've requested that they check." ] ],
    "ticket_sales_producer_daily" => [ [ "You asked for this note;", "You requested this note;" ] ],
    "account_deletion_requested" => [
      [ "Someone asked to delete their account", "Someone requested account deletion" ],
      [ "asked to delete their CocoScout account", "requested deleting their CocoScout account" ],
      [ "The date they asked", "The date of the request" ]
    ],
    "follower_email_footer" => [ [ "because you asked to hear from", "because you signed up to hear from" ] ],
    "shift_canceled" => [ [ "Questions? Ask a manager at", "Questions? Contact a manager at" ] ],
    "staff_shift_removed" => [ [ "Questions? Ask a manager at", "Questions? Contact a manager at" ] ],
    "shift_vacancy_covered_invitee" => [
      [ "Shift covered (others asked)", "Shift covered (others invited)" ],
      [ "asked you about has been covered", "invited you to cover has been covered" ]
    ],
    "books_download_failed" => [
      [ "Ask for it again from Statements.", "Request it again from Statements." ],
      [ "What was asked for", "What was requested" ]
    ],
    "contract_connection_connected_by_earlier_yes" => [ [ "You weren't asked this time, because", "No approval was requested from you this time, because" ] ],
    "visual_assets_request" => [
      [ "(to the people asked)", "(to the people it's sent to)" ],
      [ "The organization asking", "The organization requesting" ]
    ],
    "visual_assets_requested" => [ [ "The organization asking", "The organization requesting" ] ],
    "visual_assets_arrived" => [ [ "The organization asking", "The organization requesting" ] ],
    "visual_assets_complete" => [ [ "The organization asking", "The organization requesting" ] ],
    "request_contract_signature" => [ [ "being asked to sign", "whose signature is requested" ] ]
  }.freeze

  def up
    swap(PHRASES)
  end

  def down
    swap(PHRASES.transform_values { |pairs| pairs.map(&:reverse) })
  end

  private

  def swap(phrases)
    phrases.each do |key, pairs|
      template = Template.find_by(key: key)
      next unless template

      changes = {}
      %w[name subject body push_body].each do |column|
        next unless template.has_attribute?(column) && template[column].is_a?(String)

        text = pairs.reduce(template[column]) { |memo, (from, to)| memo.gsub(from, to) }
        changes[column] = text unless text == template[column]
      end
      variables = Array(template.available_variables).map do |variable|
        next variable unless variable.is_a?(Hash) && variable["description"].is_a?(String)

        variable.merge("description" => pairs.reduce(variable["description"]) { |memo, (from, to)| memo.gsub(from, to) })
      end
      changes["available_variables"] = variables unless variables == Array(template.available_variables)
      template.update_columns(changes) if changes.any?
    end
  end
end
