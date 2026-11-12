# frozen_string_literal: true

# Books starts with its categories (Tim, 2026-11-02): until someone who can
# change the books has gone through the setup and said "These are my
# categories", every Books page sends them there. Someone who can only
# look isn't asked; they see the books as they are.
module BooksCategoriesGate
  extend ActiveSupport::Concern

  included do
    before_action :require_books_categories_setup
  end

  private

  def require_books_categories_setup
    org = Current.organization
    return if org.nil? || org.books_categories_set_up_at.present?
    return unless OrganizationAccess.allows?(Current.user, org, :books, :manage)

    redirect_to manage_money_books_setup_path, notice: "Books starts with its categories. Set them up once, and the books are yours."
  end
end
