# frozen_string_literal: true

# The boxes at ticket checkout that add a buyer to mailing lists (Mailing
# lists, V1.1): a Pro organization with the setting on shows its main list's
# box, plus one for each list that collects from the production. Never at the
# door. Ticked by default unless the organization says otherwise.
class FollowCheckout
  def self.boxes_for(organization, production: nil, at_door: false)
    return [] if at_door || organization.nil? || !organization.on_paid_plan?

    profile = TicketingProfile.find_by(organization: organization)
    return [] unless profile&.follow_at_checkout

    production ? MailingList.for_checkout(production) : [ MailingList.main_for!(organization) ]
  end

  def self.ticked_by_default?(organization)
    TicketingProfile.find_by(organization: organization)&.follow_boxes_ticked != false
  end

  # The ticked ones among the boxes shown.
  def self.chosen_ids(params, boxes)
    Array(params[:follow_list_ids]).map(&:to_i) & boxes.map(&:id)
  end
end
