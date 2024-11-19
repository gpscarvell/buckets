provider "google" {
  project = "your-project-id"
  region  = "us-central1"
}

resource "google_storage_bucket" "buckets" {
  for_each = var.buckets

  name          = each.value.name
  location      = "US"
  storage_class = "STANDARD"

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_storage_bucket_iam_binding" "buckets_iam_binding" {
  for_each = {
    for bucket, config in var.buckets :
    bucket => config.iam_roles
  }

  bucket = google_storage_bucket.buckets[each.key].name
  role   = each.value[0].role

  members = flatten([for role in each.value : role.members])
}

output "bucket_names" {
  value = [for bucket in google_storage_bucket.buckets : bucket.name]
}

#
#resource "google_storage_bucket_iam_binding" "buckets_iam_binding" {
#  for_each = {
#    for bucket, config in var.buckets :
#    bucket => config.iam_roles
#  }
#
#  bucket = google_storage_bucket.buckets[each.key].name
#  role   = each.value[0].role
#
#  members = flatten([for role in each.value : role.members])
#}
