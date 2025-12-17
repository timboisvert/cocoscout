# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CalendarSyncMailer, type: :mailer do
  describe '#event_invitation' do
    let(:person) { create(:person, email: 'test@example.com', name: 'Test Person') }
    let(:production) { create(:production, name: 'Test Production') }
    let(:show) { create(:show, production: production, event_type: 'show', secondary_name: 'Opening Night') }

    context 'with REQUEST action' do
      let(:mail) { CalendarSyncMailer.event_invitation(person, show, 'REQUEST') }

      it 'sends to the person\'s email' do
        expect(mail.to).to eq([person.email])
      end

      it 'includes the production name in the subject' do
        expect(mail.subject).to include(production.name)
      end

      it 'attaches an iCal file' do
        expect(mail.attachments).not_to be_empty
        expect(mail.attachments.first.filename).to eq('event.ics')
      end

      it 'includes event details in the iCal attachment' do
        ical_content = mail.attachments.first.body.to_s
        expect(ical_content).to include('BEGIN:VCALENDAR')
        expect(ical_content).to include('BEGIN:VEVENT')
        expect(ical_content).to include('METHOD:REQUEST')
        expect(ical_content).to include('END:VEVENT')
        expect(ical_content).to include('END:VCALENDAR')
      end
    end

    context 'with UPDATE action' do
      let(:mail) { CalendarSyncMailer.event_invitation(person, show, 'UPDATE') }

      it 'uses UPDATE method in iCal' do
        ical_content = mail.attachments.first.body.to_s
        expect(ical_content).to include('METHOD:UPDATE')
      end
    end

    context 'with CANCEL action' do
      let(:mail) { CalendarSyncMailer.event_invitation(person, show, 'CANCEL') }

      it 'includes "Cancelled" in the subject' do
        expect(mail.subject).to include('Cancelled')
      end

      it 'uses CANCEL method in iCal' do
        ical_content = mail.attachments.first.body.to_s
        expect(ical_content).to include('METHOD:CANCEL')
        expect(ical_content).to include('STATUS:CANCELLED')
      end
    end
  end
end
