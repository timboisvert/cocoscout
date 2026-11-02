# frozen_string_literal: true

module Manage
  # Money → Books → Set up your categories (Tim, 2026-11-02): the first thing
  # Books asks for, and the one place to change it later. A few questions
  # about the organization, the built-in categories each answer recommends,
  # the organization's own, and "These are my categories". Until that is
  # said, every Books page comes here (BooksCategoriesGate). Needs manage on
  # Books; someone who can only look is sent to the books.
  class BooksSetupController < Manage::ManageController
    before_action :require_change!

    def show
      @setup = BooksCategorySetup.new(Current.organization)
      @custom = Current.organization.ledger_accounts.active.where(system: false).order(:name).to_a
    end

    def update
      setup = BooksCategorySetup.new(Current.organization, profile: params[:profile])
      return redirect_to manage_money_books_setup_path, alert: "Say what kind of organization this is first." unless setup.answered?

      first_time = Current.organization.books_categories_set_up_at.nil?
      setup.save!(by: Current.user, offered: params[:offered], custom: custom_params)
      if first_time
        redirect_to manage_money_books_path, notice: "Your categories are set. Books is yours; change them any time on Money settings → Books."
      else
        redirect_to manage_money_settings_section_path(section: "books"), notice: "Your categories are saved."
      end
    end

    private

    def custom_params
      params.fetch(:custom, {}).permit(income: [], expense: []).to_h
    end

    def require_change!
      return if OrganizationAccess.allows?(Current.user, Current.organization, :books, :manage)

      redirect_to manage_money_books_path, alert: "You can look at the books but not set them up."
    end
  end
end
