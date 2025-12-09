# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Manage::Groups::EmailLogs', type: :request do
  let!(:organization) { create(:organization) }
  let!(:user) { create(:user) }
  let!(:group) { create(:group) }

  before do
    # Associate group with organization
    group.organizations << organization unless group.organizations.include?(organization)
    
    # Sign in user and set current organization
    sign_in user
    allow_any_instance_of(ApplicationController).to receive(:Current).and_return(
      OpenStruct.new(user: user, organization: organization)
    )
  end

  describe 'GET /manage/groups/:group_id/email_logs' do
    let!(:email_log1) do
      create(:email_log,
             user: user,
             recipient: group.email,
             recipient_type: 'Group',
             recipient_id: group.id,
             subject: 'Group Email 1',
             sent_at: 2.days.ago)
    end

    let!(:email_log2) do
      create(:email_log,
             user: user,
             recipient: group.email,
             recipient_type: 'Group',
             recipient_id: group.id,
             subject: 'Group Email 2',
             sent_at: 1.day.ago)
    end

    it 'displays email logs for the group' do
      get "/manage/groups/#{group.id}/email_logs"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Group Email 1')
      expect(response.body).to include('Group Email 2')
    end

    it 'filters email logs by search term' do
      get "/manage/groups/#{group.id}/email_logs", params: { search: 'Group Email 1' }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Group Email 1')
      expect(response.body).not_to include('Group Email 2')
    end
  end

  describe 'GET /manage/groups/:group_id/email_logs/:id' do
    let!(:group_member) { create(:person) }
    let!(:email_log) do
      create(:email_log,
             user: user,
             recipient: group.email,
             recipient_type: 'Group',
             recipient_id: group.id,
             subject: 'Group Email',
             body: '<p>This is the group email body</p>',
             sent_at: 1.day.ago)
    end

    before do
      # Add member to the group
      group.members << group_member unless group.members.include?(group_member)
    end

    it 'displays the email log details with group members' do
      get "/manage/groups/#{group.id}/email_logs/#{email_log.id}"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Group Email')
      expect(response.body).to include('This is the group email body')
      expect(response.body).to include(group_member.name)
    end
  end
end
