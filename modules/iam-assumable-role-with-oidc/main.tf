locals {
  aws_account_id = var.aws_account_id != "" ? var.aws_account_id : data.aws_caller_identity.current.account_id
  # clean URLs of https:// prefix
  urls = [
    for url in compact(distinct(concat(var.provider_urls, [var.provider_url]))) :
    replace(url, "https://", "")
  ]
  number_of_role_policy_arns = coalesce(var.number_of_role_policy_arns, length(var.role_policy_arns))
  role_sts_externalid        = flatten([var.role_sts_externalid])
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_iam_policy_document" "assume_role_with_oidc" {
  count = var.create_role ? 1 : 0

  statement {

    effect = "Allow"

    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [for url in local.urls : "arn:${data.aws_partition.current.partition}:iam::${local.aws_account_id}:oidc-provider/${url}"]
    }

    dynamic "condition" {
      for_each = length(var.oidc_fully_qualified_subjects) > 0 ? local.urls : []

      content {
        test     = "StringEquals"
        variable = "${each.value}:sub"
        values   = var.oidc_fully_qualified_subjects
      }
    }

    dynamic "condition" {
      for_each = length(var.oidc_subjects_with_wildcards) > 0 ? local.urls : []

      content {
        test     = "StringLike"
        variable = "${each.value}:sub"
        values   = var.oidc_subjects_with_wildcards
      }
    }

    dynamic "condition" {
      for_each = length(var.oidc_fully_qualified_audiences) > 0 ? local.urls : []

      content {
        test     = "StringLike"
        variable = "${each.value}:aud"
        values   = var.oidc_fully_qualified_audiences
      }
    }
  }

  dynamic "statement" {
    for_each = length(concat(var.trusted_role_arns, var.trusted_role_services)) > 0 ? [true] : []

    content {
      effect = "Allow"

      actions = var.trusted_role_actions

      dynamic "principals" {
        for_each = length(var.trusted_role_arns) > 0 ? [true] : []
        content {
          type        = "AWS"
          identifiers = var.trusted_role_arns
        }
      }

      dynamic "principals" {
        for_each = length(var.trusted_role_services) > 0 ? [true] : []

        content {
          type        = "Service"
          identifiers = var.trusted_role_services
        }
      }

      dynamic "condition" {
        for_each = length(local.role_sts_externalid) != 0 ? [true] : []
        content {
          test     = "StringEquals"
          variable = "sts:ExternalId"
          values   = local.role_sts_externalid
        }
      }

    }

  }
}

resource "aws_iam_role" "this" {
  count = var.create_role ? 1 : 0

  name                 = var.role_name
  name_prefix          = var.role_name_prefix
  description          = var.role_description
  path                 = var.role_path
  max_session_duration = var.max_session_duration

  force_detach_policies = var.force_detach_policies
  permissions_boundary  = var.role_permissions_boundary_arn

  assume_role_policy = join("", data.aws_iam_policy_document.assume_role_with_oidc.*.json)

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "custom" {
  count = var.create_role ? local.number_of_role_policy_arns : 0

  role       = join("", aws_iam_role.this.*.name)
  policy_arn = var.role_policy_arns[count.index]
}
