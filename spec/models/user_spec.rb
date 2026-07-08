# frozen_string_literal: true

require 'rails_helper'

describe User, type: :model do
  it 'is valid with valid attributes' do
    expect(build(:user)).to be_valid
  end

  it 'is invalid without an email_address' do
    user = build(:user, email_address: nil)
    expect(user).not_to be_valid
  end

  it 'is invalid without a password' do
    user = build(:user, password: nil)
    expect(user).not_to be_valid
  end

  describe '#can_access_production?' do
    let(:org) { create(:organization) }
    let(:active_production) { create(:production, organization: org) }
    let(:archived_production) { create(:production, organization: org, archived_at: Time.current) }

    around do |example|
      Current.organization = org
      example.run
      Current.organization = nil
    end

    context 'when the user is an org manager' do
      let(:user) { create(:user) }
      before { create(:organization_role, :manager, user: user, organization: org) }

      it 'can open an active production' do
        expect(user.can_access_production?(active_production)).to be(true)
      end

      it 'can open an ARCHIVED production (the bug fix)' do
        expect(user.can_access_production?(archived_production)).to be(true)
      end

      it 'cannot open a production in a different organization' do
        other = create(:production, organization: create(:organization))
        expect(user.can_access_production?(other)).to be(false)
      end

      it 'is false for nil' do
        expect(user.can_access_production?(nil)).to be(false)
      end
    end

    context 'when the user has no role in the org' do
      let(:user) { create(:user) }

      it 'cannot open the production (even active)' do
        expect(user.can_access_production?(active_production)).to be(false)
      end
    end

    context 'when the user is an org viewer' do
      let(:user) { create(:user) }
      before { create(:organization_role, user: user, organization: org) } # default company_role is viewer

      it 'can also open archived productions' do
        expect(user.can_access_production?(archived_production)).to be(true)
      end
    end
  end
end
