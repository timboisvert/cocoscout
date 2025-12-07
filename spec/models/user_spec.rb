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
end
