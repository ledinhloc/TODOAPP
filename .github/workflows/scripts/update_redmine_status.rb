require 'net/http'
require 'uri'
require 'json'

redmine_url = ENV['REDMINE_URL']
redmine_api_key = ENV['REDMINE_API_KEY']

title = ARGV[0]
body = ARGV[1]
state = ARGV[2]
merged = ARGV[3] == 'true' # Chuyển đổi chuỗi 'true' thành boolean
github_url = ARGV[4]
head_ref = ARGV[5]
base_ref = ARGV[6]
github_repo = ARGV[7]

# Regular expression để tìm các issue Redmine ID
issue_regex = /#([A-Za-z0-9_-]+-\d+|\d+)/

# Tìm tất cả các issue ID được đề cập
issue_ids_with_prefix = (title.scan(issue_regex) + body.scan(issue_regex)).flatten.uniq

# Ánh xạ giữa repository GitHub và project Redmine (CẦN CẬP NHẬT)
repo_to_project_mapping = {
  'your-org/your-repo' => 'your-redmine-project-identifier',
  'another-org/another-repo' => 'another-redmine-project'
  # Thêm các ánh xạ khác nếu cần
}

# ID trạng thái Redmine
STATUS_OPEN = 1
STATUS_MERGED = 2

redmine_notes_template_merged = "[GitHub Pull Request Merged]\nTitle: #{title}\nURL: #{github_url}\nSource Branch: #{head_ref}\nTarget Branch: #{base_ref}"
redmine_notes_template_other = "[GitHub Pull Request]\nTitle: #{title}\nURL: #{github_url}\nSource Branch: #{head_ref}\nTarget Branch: #{base_ref}\nState: #{state}"

def update_issue_status(project_id, issue_id, status_id, notes)
  uri = URI.parse("#{redmine_url}/issues/#{issue_id}.json?project_id=#{project_id}")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == 'https'

  request = Net::HTTP::Put.new(uri.path, { 'Content-Type' => 'application/json', 'X-Redmine-API-Key' => redmine_api_key })
  request.body = JSON.generate({
    issue: {
      status_id: status_id,
      notes: notes
    }
  })

  response = http.request(request)
  if response.code.to_i >= 300
    puts "Failed to update issue #{project_id}-#{issue_id}: #{response.code} - #{response.body}"
  else
    puts "Successfully updated issue #{project_id}-#{issue_id} to status #{status_id}"
  end
end

issue_ids_with_prefix.each do |issue_ref|
  project_id_from_repo = repo_to_project_mapping[github_repo]

  if project_id_from_repo
    issue_id_only = issue_ref.gsub(/^[A-Za-z0-9_-]+-/, '')

    if merged
      update_issue_status(project_id_from_repo, issue_id_only, STATUS_MERGED, redmine_notes_template_merged)
    elsif state == 'open' || state == 'reopened' || state == 'edited' || state == 'synchronize'
      # Bạn có thể chọn không cập nhật trạng thái trong các trường hợp này
      # Hoặc bạn có thể cập nhật sang một trạng thái khác (ví dụ: 'In Progress' - ID 2)
      # update_issue_status(project_id_from_repo, issue_id_only, STATUS_IN_PROGRESS, redmine_notes_template_other)
      puts "Pull Request is open/reopened/edited/synchronized, no status change for #{project_id_from_repo}-#{issue_id_only}"
    elsif state == 'closed' && !merged
      # Xử lý trường hợp pull request bị đóng mà không được merge (ví dụ: chuyển sang trạng thái 'Rejected' - ID tùy chỉnh)
      # update_issue_status(project_id_from_repo, issue_id_only, STATUS_REJECTED, redmine_notes_template_other)
      puts "Pull Request was closed without merging, no status change for #{project_id_from_repo}-#{issue_id_only}"
    end
  else
    puts "No Redmine project mapping found for GitHub repository: #{github_repo}"
  end
end
