# frozen_string_literal: true

require 'rails_helper'
require 'stringio'

RSpec.describe ApplicationHelper, type: :helper do
  let(:image_path) { Rails.root.join('app/assets/images/cocoscoutsmall.png') }

  describe 'attachment helpers' do
    it 'identifies pending attachments for unsaved records' do
      person = Person.new(name: 'Test Person', email: 'pending@example.com')
      person.headshot.attach(io: StringIO.new(File.binread(image_path)), filename: 'headshot.png',
                             content_type: 'image/png')

      expect(displayable_attachment?(person.headshot)).to be(false)
      expect(pending_attachment?(person.headshot)).to be(true)
    end

    it 'identifies persisted attachments for saved records' do
      person = create(:person, email: 'persisted@example.com')
      person.headshot.attach(io: StringIO.new(File.binread(image_path)), filename: 'headshot.png',
                             content_type: 'image/png')

      expect(displayable_attachment?(person.headshot)).to be(true)
      expect(pending_attachment?(person.headshot)).to be(false)
    end
  end
end
