# Refreshes data/terraform_modules.yml (rendered by
# source/platform-catalogue/terraform-modules/index.html.md.erb) from the
# .hmcts/catalogue.yaml file each Terraform module repo owns. Discovery is
# via the 'terraform-module' GitHub topic, not a hardcoded repo list, so
# newly tagged repos are picked up automatically.
#
# Deliberately stdlib-only (net/http, json, yaml) to match rakelib/checks.rake
# rather than adding a new gem for a handful of GitHub API calls.

require 'net/http'
require 'uri'
require 'json'
require 'yaml'

GITHUB_ORG = 'hmcts'.freeze
CATALOGUE_TOPIC = 'terraform-module'.freeze
CATALOGUE_DATA_FILE = 'data/terraform_modules.yml'.freeze
REQUIRED_CATALOGUE_FIELDS = %w[name type category description owner lifecycle links].freeze
ALLOWED_LIFECYCLES = %w[supported deprecated experimental].freeze

def github_get(uri_string)
  uri = URI(uri_string)
  request = Net::HTTP::Get.new(uri)
  request['User-Agent'] = 'hmcts-platform-catalogue'
  request['Accept'] = 'application/vnd.github+json'
  token = ENV.fetch('GH_TOKEN', nil)
  request['Authorization'] = "Bearer #{token}" if token
  Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
end

def discover_module_repos
  response = github_get("https://api.github.com/search/repositories?q=org:#{GITHUB_ORG}+topic:#{CATALOGUE_TOPIC}&per_page=100")
  unless response.is_a?(Net::HTTPSuccess)
    puts "warning: could not list repos with topic '#{CATALOGUE_TOPIC}' (#{response.code}); skipping refresh"
    return []
  end
  JSON.parse(response.body)['items'] || []
end

def fetch_catalogue_yaml(repo_name, default_branch)
  url = "https://raw.githubusercontent.com/#{GITHUB_ORG}/#{repo_name}/#{default_branch}/.hmcts/catalogue.yaml"
  response = github_get(url)
  return nil unless response.is_a?(Net::HTTPSuccess)

  YAML.safe_load(response.body, permitted_classes: [Date])
rescue StandardError => e
  puts "warning: #{repo_name} - .hmcts/catalogue.yaml did not parse (#{e.class}: #{e.message})"
  nil
end

def validate_catalogue_entry(repo_name, entry)
  problems = []
  problems << "missing #{(REQUIRED_CATALOGUE_FIELDS - entry.keys).join(', ')}" unless (REQUIRED_CATALOGUE_FIELDS - entry.keys).empty?
  if entry['lifecycle'] && !ALLOWED_LIFECYCLES.include?(entry['lifecycle'])
    problems << "lifecycle '#{entry['lifecycle']}' not one of #{ALLOWED_LIFECYCLES.join(', ')}"
  end
  if entry['lifecycle'] == 'deprecated' && entry['replacement'].to_s.empty?
    problems << 'lifecycle is deprecated but replacement is missing'
  end
  if entry['links'].is_a?(Hash) && entry['links']['repository'].to_s.empty?
    problems << 'links.repository is missing'
  end
  return true if problems.empty?

  puts "warning: #{repo_name} - invalid .hmcts/catalogue.yaml (#{problems.join('; ')})"
  false
end

desc 'Refresh the Platform Catalogue Terraform modules data from GitHub'
task :'catalogue:refresh' do
  repos = discover_module_repos
  puts "found #{repos.length} repo(s) tagged '#{CATALOGUE_TOPIC}'"

  discovered = repos.filter_map do |repo|
    entry = fetch_catalogue_yaml(repo['name'], repo['default_branch'])
    unless entry
      puts "warning: #{repo['name']} - no .hmcts/catalogue.yaml on #{repo['default_branch']}, skipping"
      next nil
    end
    next nil unless validate_catalogue_entry(repo['name'], entry)

    entry.merge('repo' => repo['name'])
  end

  existing = File.exist?(CATALOGUE_DATA_FILE) ? (YAML.load_file(CATALOGUE_DATA_FILE) || []) : []
  discovered_repo_names = discovered.map { |e| e['repo'] }
  kept_bootstrap = existing.select { |e| e['bootstrap_sample'] && !discovered_repo_names.include?(e['repo']) }

  final = (discovered + kept_bootstrap).sort_by { |e| e['name'].to_s }
  File.write(CATALOGUE_DATA_FILE, final.to_yaml)

  puts "published #{discovered.length} discovered entrie(s), kept #{kept_bootstrap.length} bootstrap sample(s), " \
       "wrote #{final.length} total to #{CATALOGUE_DATA_FILE}"
end
