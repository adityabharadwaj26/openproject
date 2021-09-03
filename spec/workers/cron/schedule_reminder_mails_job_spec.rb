#-- encoding: UTF-8

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) 2012-2021 the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See docs/COPYRIGHT.rdoc for more details.
#++

require 'spec_helper'

describe Cron::ScheduleReminderMailsJob, type: :job do

  # As it is hard to mock Postgres's "now()" method, in the specs here we need to adopt the slot time
  # relative to the local time of the user that we want to hit.
  let(:current_utc_time) { Time.now.getutc }
  let(:slot_time) { hitting_slot_for(hitting_user, current_utc_time) } # ie. "08:00", "08:30"

  let(:hitting_user) { paris_user }
  let(:paris_user) { FactoryBot.create(:user, preferences: { time_zone: "Paris" }) } # time_zone in winter is +01:00
  let(:no_zone_user) { FactoryBot.create(:user) } # time_zone is nil

  subject(:perform_job) do
    described_class.new.perform
  end

  before do
    allow(Setting).to receive(:notification_email_digest_time).and_return(slot_time)
  end

  context '#perform' do
    context 'with paris_user as hitting_user' do
      let(:moscow_user) { FactoryBot.create(:user, preferences: { time_zone: "Moscow" }) } # time_zone all year is +03:00
      let(:greenland_user) { FactoryBot.create(:user, preferences: { time_zone: "Greenland" }) } # time_zone in winter is -03:00

      before do
        allow(Time).to receive(:now).and_return(current_utc_time)
      end

      it 'schedules ReminderMailJobs for all users that subscribed for that slot in their local time' do
        # `hitting_user` is `paris_user`.
        # `slot_time` (expressed string in local time) is set to be at the beginning of the first or second half hour
        # block of the started hour.
        expect { perform_job }
            .to enqueue_job(Mails::ReminderJob)
                    .with(hitting_user.id)

        # `moscow_user` is in a different time zone (higher offset than Paris) so should not hit for the same `slot_time`
        expect { perform_job }
            .to_not enqueue_job(Mails::ReminderJob)
                    .with(moscow_user.id)

        # `greenland_user` is in a different time (lower offset than Paris) so should not hit for the same `slot_time`
        expect { perform_job }
            .to_not enqueue_job(Mails::ReminderJob)
                        .with(greenland_user.id)

        # `no_zone_user` should fall back to UTC time zone and thus have lower offset as `paris_user` and not hit
        expect { perform_job }
            .to_not enqueue_job(Mails::ReminderJob)
                        .with(no_zone_user.id)
      end
    end

    context 'slot_time in UTC' do
      let(:hitting_user) { no_zone_user }

      it 'schedules a job for users without timezone set' do
        expect { perform_job }
            .to enqueue_job(Mails::ReminderJob)
                    .with(hitting_user.id)
      end
    end

    context 'hitting user is not active' do
      let(:hitting_user) do
        paris_user.locked!
        paris_user
      end

      it 'does not schedule for users that are not active' do
        expect { perform_job }
            .to_not enqueue_job(Mails::ReminderJob)
                    .with(hitting_user.id)
      end
    end
  end

  # context '#latest_slot' do
  #   context 'when within first half of an hour' do
  #     before do
  #       allow(Time).to receive(:current).and_return()
  #     end
  #   end
  # end
  #
  private

  # Calculates a slot in the user's local time that hits for scheduling reminder mail jobs
  def hitting_slot_for(user, current_utc_time)
    local_time = current_utc_time.in_time_zone(user.time_zone)
    "#{'%02d' % local_time.hour}:#{local_time.min <= 30 ? '00' : '30'}"
  end
end
