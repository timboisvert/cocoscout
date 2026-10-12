# frozen_string_literal: true

module Manage
  # "Email the setup link": sends a payee their own bank setup link
  # (BankSetupLink). Only the organization's own payees: its people, its
  # contractors and their people, and the instructors of its courses.
  class BankSetupEmailsController < Manage::ManageController
    def create
      payee = find_payee
      BankSetupLink.send!(organization: Current.organization, payee: payee, by: Current.user)
      redirect_back_or_to manage_path, notice: "Bank setup link emailed to #{payee.name}."
    rescue BankSetupLink::Error => e
      redirect_back_or_to manage_path, alert: e.message
    end

    private

    def find_payee
      org = Current.organization
      case params[:payee_type]
      when "Contractor"
        org.contractors.find(params[:payee_id])
      when "Person"
        instructors = CourseOfferingInstructor.joins(course_offering: :production)
                                              .where(productions: { organization_id: org.id }).select(:person_id)
        Person.where(id: org.people.select(:id))
              .or(Person.where(id: org.contractors.select(:person_id)))
              .or(Person.where(id: instructors))
              .find(params[:payee_id])
      else
        raise ActiveRecord::RecordNotFound
      end
    end
  end
end
