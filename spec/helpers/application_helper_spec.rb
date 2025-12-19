# frozen_string_literal: true

require 'rails_helper'
require 'stringio'

RSpec.describe ApplicationHelper, type: :helper do
  let(:image_path) { Rails.root.join('app/assets/images/cocoscoutsmall.png') }

  describe 'attachment helpers' do
    it 'identifies pending attachments for unsaved records' do
      profile_headshot = ProfileHeadshot.new(position: 0, is_primary: true)
      profile_headshot.image.attach(io: StringIO.new(File.binread(image_path)), filename: 'headshot.png',
                                    content_type: 'image/png')

      expect(displayable_attachment?(profile_headshot.image)).to be(false)
      expect(pending_attachment?(profile_headshot.image)).to be(true)
    end

    it 'identifies persisted attachments for saved records' do
      person = create(:person, email: 'persisted@example.com')
      profile_headshot = person.profile_headshots.create!(position: 0, is_primary: true)
      profile_headshot.image.attach(io: StringIO.new(File.binread(image_path)), filename: 'headshot.png',
                                    content_type: 'image/png')

      expect(displayable_attachment?(profile_headshot.image)).to be(true)
      expect(pending_attachment?(profile_headshot.image)).to be(false)
    end
  end
end
