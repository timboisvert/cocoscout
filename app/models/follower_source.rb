# frozen_string_literal: true

# One way a follower arrived or bought: tickets at checkout, added by hand,
# pasted, from Contacts, or added by a producer a list is shared with. The
# "where they came from" on every list, and what segments read.
class FollowerSource < ApplicationRecord
  KINDS = %w[checkout manual paste contacts added_by_share].freeze

  belongs_to :follower
  belongs_to :production, optional: true
  belongs_to :show, optional: true
  belongs_to :ticket_order, optional: true
  belongs_to :mailing_list, optional: true
  belongs_to :added_by_person, class_name: "Person", optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :occurred_at, presence: true

  scope :tickets, -> { where(kind: "checkout") }

  # "Tickets · Laugh-Along, Live! · Oct 17", "Added by Dan Feltey · Sep 30".
  # viewer: the Person reading it, so their own additions say "Added by you".
  def label(viewer: nil)
    date = occurred_at.strftime("%b %-d")
    case kind
    when "checkout"
      [ "Tickets", production&.name, date ].compact.join(" · ")
    when "added_by_share"
      who = added_by_person && viewer && added_by_person_id == viewer.id ? "you" : added_by_person&.name
      [ "Added by #{who || 'a producer'}", date ].join(" · ")
    when "contacts"
      [ "From Contacts", date ].join(" · ")
    else
      who = added_by_person && viewer && added_by_person_id == viewer.id ? "you" : added_by_person&.name
      [ who ? "Added by #{who}" : "Added by hand", date ].join(" · ")
    end
  end
end
