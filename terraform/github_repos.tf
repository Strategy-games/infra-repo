resource "github_repository" "infra_repo" {
  name        = "infra-repo"
  description = "CI/CDパイプライン管理・k8sマニフェスト・Terraform IaC"
  visibility  = "private"

  has_issues   = true
  has_projects = false
  has_wiki     = false

  delete_branch_on_merge = true
}

resource "github_branch_protection" "infra_main" {
  repository_id = github_repository.infra_repo.node_id
  pattern       = "main"

  required_pull_request_reviews {
    required_approving_review_count = 1
    dismiss_stale_reviews           = true
    restrict_dismissals             = true
    dismissal_restrictions          = [github_team.infra.node_id]
  }

  required_status_checks {
    strict   = true
    contexts = ["terraform-plan"]
  }

  enforce_admins = false
}

resource "github_branch_protection" "infra_debug" {
  repository_id = github_repository.infra_repo.node_id
  pattern       = "debug"

  required_pull_request_reviews {
    required_approving_review_count = 1
    dismiss_stale_reviews           = true
  }

  required_status_checks {
    strict   = true
    contexts = ["terraform-plan"]
  }
}

resource "github_team_repository" "infra_team_infra_repo" {
  team_id    = github_team.infra.id
  repository = github_repository.infra_repo.name
  permission = "maintain"
}

resource "github_team_repository" "mc_ops_infra_repo" {
  team_id    = github_team.mc_ops.id
  repository = github_repository.infra_repo.name
  permission = "push"
}
