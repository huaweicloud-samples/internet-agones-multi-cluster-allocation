# SWR repository visibility is managed in swr_repos.tf (huaweicloud_swr_repository
# resources with is_public = true). The whole-organization "visibility" attribute
# is not exposed by the huaweicloud_swr_organization resource, so we set it per
# repository instead. See swr_repos.tf for details.
