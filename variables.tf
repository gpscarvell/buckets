variable "buckets" {
  description = "Map of GCS bucket configurations, including IAM members"
  type = map(object({
    name     = string
    iam_roles = list(object({
      role    = string
      members = list(string)
    }))
  }))
  default = {
    "bucket1" = {
      name     = "bucket1"
      iam_roles = [
        {
          role    = "roles/storage.admin"
          members = ["user:admin@example.com", "serviceAccount:my-service-account@example.com"]
        },
        {
          role    = "roles/storage.objectViewer"
          members = ["user:viewer@example.com"]
        }
      ]
    },
    "bucket2" = {
      name     = "bucket2"
      iam_roles = [
        {
          role    = "roles/storage.objectCreator"
          members = ["user:creator@example.com"]
        }
      ]
    }
  }
}

