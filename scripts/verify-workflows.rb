#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "yaml"

ROOT = File.expand_path("..", __dir__)
WORKFLOWS = Dir[File.join(ROOT, ".github", "workflows", "*.yml")].sort.freeze

def fail_check(message)
  warn "ERROR: #{message}"
  exit 1
end

def exact_permissions(document, expected, path)
  actual = document.fetch("permissions", {})
  fail_check("#{path} permissions differ: #{actual.inspect}") unless actual == expected
end

documents = {}
WORKFLOWS.each do |path|
  document = YAML.safe_load(File.read(path, encoding: "UTF-8"), aliases: true)
  documents[File.basename(path)] = document

  document.fetch("jobs", {}).each_value do |job|
    job.fetch("steps", []).each do |step|
      if step["uses"]
        reference = step.fetch("uses")
        unless reference.match?(%r{\Aactions/[^@]+@[0-9a-f]{40}\z})
          fail_check("external action is not pinned to a full SHA: #{reference}")
        end
      end

      next unless step["run"]

      _stdout, stderr, status = Open3.capture3("bash", "-n", "-c", step.fetch("run"))
      fail_check("bash syntax failed in #{path} step #{step['name']}: #{stderr}") unless status.success?
    end
  end
end

exact_permissions(
  documents.fetch("verify-web.yml"),
  { "contents" => "read" },
  "verify-web.yml"
)
exact_permissions(
  documents.fetch("merge-guard.yml"),
  { "contents" => "write", "pull-requests" => "write" },
  "merge-guard.yml"
)
exact_permissions(
  documents.fetch("deploy-pages.yml"),
  {
    "contents" => "read",
    "actions" => "read",
    "pages" => "write",
    "id-token" => "write"
  },
  "deploy-pages.yml"
)
exact_permissions(
  documents.fetch("publish-itch.yml"),
  { "contents" => "read", "actions" => "read" },
  "publish-itch.yml"
)

guard = File.read(File.join(ROOT, ".github", "workflows", "merge-guard.yml"), encoding: "UTF-8")
deploy = File.read(File.join(ROOT, ".github", "workflows", "deploy-pages.yml"), encoding: "UTF-8")
itch = File.read(File.join(ROOT, ".github", "workflows", "publish-itch.yml"), encoding: "UTF-8")

fail_check("Merge Guard must not check out code") if guard.include?("actions/checkout")
%w[HEAD_REPO pull_request_target].each do |marker|
  fail_check("Merge Guard is missing #{marker}") unless guard.include?(marker)
end

[
  "workflow_dispatch",
  "workflow_run.id",
  "workflow_run.pull_requests",
  "github-actions[bot]",
  "head_tree",
  "merge_tree",
  "for attempt in {1..60}",
  "::warning::",
  "steps.authorize.outputs.run_id",
  "Confirm main is still current"
].each do |marker|
  fail_check("Deploy Pages is missing #{marker}") unless deploy.include?(marker)
end

# Both publishers accept an artifact through the same gate. Divergence between
# the two copies would be a security bug, so they must stay byte-identical.
def authorize_script(document, path)
  step = document
         .fetch("jobs")
         .each_value
         .flat_map { |job| job.fetch("steps", []) }
         .find { |candidate| candidate["id"] == "authorize" }
  fail_check("#{path} has no step with id: authorize") if step.nil?
  step
end

pages_gate = authorize_script(documents.fetch("deploy-pages.yml"), "deploy-pages.yml")
itch_gate = authorize_script(documents.fetch("publish-itch.yml"), "publish-itch.yml")
if pages_gate != itch_gate
  fail_check(
    "the authorize step differs between deploy-pages.yml and publish-itch.yml; " \
    "both publishers must share one gate verbatim"
  )
end

fail_check("Publish to itch.io must not check out code") if itch.include?("actions/checkout")

# The key must reach exactly one step, and only after the gate has passed.
key_uses = itch.scan("secrets.butler_api_key").length
fail_check("expected one secrets.butler_api_key reference, found #{key_uses}") if key_uses != 1

itch_steps = documents
             .fetch("publish-itch.yml")
             .fetch("jobs")
             .each_value
             .flat_map { |job| job.fetch("steps", []) }
key_steps = itch_steps.select { |step| step.to_s.include?("secrets.butler_api_key") }
if key_steps.length != 1
  fail_check("the butler key must appear in exactly one step, found #{key_steps.length}")
end
key_step = key_steps.fetch(0)
unless key_step.fetch("name", "") == "Push the site to itch.io"
  fail_check("the butler key is on step '#{key_step['name']}', not the push step")
end
unless key_step.fetch("if", "").include?("steps.freshness.outputs.current")
  fail_check("the push step does not wait for the freshness check")
end
%w[
  steps.freshness.outputs.current
  itch_target
  broth.itch.zone
].each do |marker|
  fail_check("Publish to itch.io is missing #{marker}") unless itch.include?(marker)
end

# A caller that inherits secrets would hand every secret it holds to a called
# workflow. Callers are documented here, so the ban is asserted here too.
documents.each do |name, document|
  document.fetch("jobs", {}).each do |job_name, job|
    if job["secrets"] == "inherit"
      fail_check("#{name} job #{job_name} uses secrets: inherit")
    end
  end
end
# Only the caller examples, so the prose may still name the thing it forbids.
readme = File.read(File.join(ROOT, "README.md"), encoding: "UTF-8")
readme.scan(/^```yaml\n(.*?)^```$/m).flatten.each do |example|
  fail_check("a README caller example uses secrets: inherit") if example.include?("secrets: inherit")
end

puts "workflow verification passed"
