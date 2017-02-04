module Retrospectives
  class FetchHours
    def self.from_timesheet(retro)
      retro.members.each do |member|
        sheet = retro.google_client.spreadsheet_by_key(member.sheet_key).
        worksheets[member.sheet_index]

        start_row = get_row(sheet, retro, retro.start_time)
        end_row = get_row(sheet, retro, retro.end_time)

        raise "Sprint not marked correctly for #{member.name}"  if start_row.nil? || end_row.nil?

        (start_row..end_row).to_a.each do |row_index|
          ticket_id = Utils.clean(sheet[row_index, retro.ticket_id_index])
          hours_spent = Utils.clean(sheet[row_index, retro.hours_spent_index]).to_f.round(2)

          next if ticket_id.nil? || ticket_id.empty?

          if retro.include_other_tickets || retro_tickets_include?(retro, ticket_id)
            member.hours_spent_timesheet[ticket_id] += hours_spent
            retro.add_ticket(ticket_id) if retro.include_other_tickets
          end
        end
      end
    end

    def self.from_jira(retro)
      retro.tickets.each do |ticket|
        retry_attempts = 0
        begin
          issue = retro.jira_client.Issue.find(ticket.id)
        rescue
          puts "WARNING : timeout [#{ticket}]. Skipping..."
          retry_attempts += 1
          if retry_attempts < 10
            retry
          end
          if issue.nil?
            puts "WARNING : Issue details not found [#{ticket.inspect}]. Skipping..."
            next
          end
        end
        ticket.description = issue.attrs['fields']['summary']
        ticket.type = issue.attrs['fields']['issuetype']['name']
        ticket.story_points = issue.attrs['fields']['customfield_10004']
        ticket.status = issue.attrs['fields']['status']['name']
        get_jira_hours(ticket, retro, issue.attrs['fields']['worklog'])
      end
    end


    private

    def self.get_row(sheet, retro, text)
      (1..sheet.num_rows).each do |row_index|
        next unless sheet[row_index, retro.sprint_delimiter_index].include?(text)

        return row_index
      end

      nil
    end

    def self.retro_tickets_include?(retro, ticket_id)
      retro.tickets.each do |ticket|
        return true if ticket.id == ticket_id
      end

      false
    end

    def self.get_jira_hours(ticket, retro, worklogs)
      # total_hours = 0.0
      # hours_logged_by_person = Hash.new(0)

      worklogs['worklogs'].each do |worklog|
        author = worklog['author']['name']
        time_in_hours = (worklog['timeSpentSeconds'] / 3600.0).round(2)

        retro.members.each do |member|
          member.hours_spent_jira[ticket.id] += time_in_hours if member.name == author
          ticket.hours_logged[author] += time_in_hours
        end
      end
    end
  end
end