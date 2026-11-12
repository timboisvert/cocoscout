# frozen_string_literal: true

# A closed month (Books V1.3, plan E2): the books are locked through a date.
# Nothing new can be dated on or before it from a form (the models refuse,
# with a reason), and anything the engine has to restate or reverse inside
# it lands on the first open day instead, so a closed month never shifts.
module BooksLock
  def self.locked?(organization, date)
    through = organization.books_locked_through
    through.present? && date.present? && date.to_date <= through
  end

  def self.first_open_day(organization)
    organization.books_locked_through + 1
  end

  def self.label(organization)
    organization.books_locked_through&.strftime("%B %-d, %Y")
  end

  # The date an entry really gets, given the lock: the date asked for, or
  # the first open day when that date is closed.
  def self.posting_date(organization, date)
    return date if date.nil? || !locked?(organization, date)

    first_open_day(organization)
  end

  # Model-side refusal, in the words the form shows.
  module Validation
    extend ActiveSupport::Concern

    class_methods do
      # unless: a predicate naming records the lock doesn't govern (an
      # invoice that is only the paper for a contract payment).
      def refuses_locked_books_on(attribute, unless: nil)
        exempt = binding.local_variable_get(:unless)
        validate do
          next if exempt && public_send(exempt)

          date = public_send(attribute)
          next if date.blank? || organization.nil? || !BooksLock.locked?(organization, date)
          # A record that already stood inside the lock can keep its date.
          next if persisted? && !public_send("#{attribute}_changed?")

          errors.add(attribute, "is in a closed month: the books are locked through #{BooksLock.label(organization)}. Unlock them on Books → Statements, or use #{BooksLock.first_open_day(organization).strftime('%b %-d')} or later.")
        end
      end
    end
  end
end
