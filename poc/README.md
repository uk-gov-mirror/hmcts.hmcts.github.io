# Local Terraform catalogue proof of concept

Each directory in `terraform-modules/` is a small stand-in for an independently owned
Terraform module repository. It contains the module's `.hmcts/catalogue.yaml` metadata
and a basic Terraform example.

Run `bundle exec rake catalogue:refresh_local` from the repository root to validate and
generate `data/terraform_modules.yml` from these local fixtures. No GitHub token or
network access is needed.

These modules are deliberately not production infrastructure. Their purpose is to make
the catalogue workflow and its lifecycle states visible locally. The metadata's `owner`
field records stewardship: it identifies an appropriate reviewer and support route, not an
exclusive owner of a shared platform asset.
