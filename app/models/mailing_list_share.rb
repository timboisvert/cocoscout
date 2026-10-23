# frozen_string_literal: true

# A list shared with a person: they see its followers in My Followers, and can
# add people and export. They can't send.
class MailingListShare < ApplicationRecord
  belongs_to :mailing_list
  belongs_to :person
  belongs_to :granted_by, class_name: "User", optional: true

  validates :person_id, uniqueness: { scope: :mailing_list_id }

  before_validation { self.granted_at ||= Time.current }

  # The lists a user can see in My Followers, through any of their people.
  def self.lists_for(user)
    return MailingList.none unless user

    MailingList.active.where(id: where(person_id: user.people.select(:id)).select(:mailing_list_id))
  end
end
