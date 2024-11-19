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


resource "google_storage_bucket_iam_member" "buckets_iam_member" {
  for_each = {
    for bucket, config in var.buckets :
    bucket => flatten([for role in config.iam_roles : for member in role.members : {
      role    = role.role
      member  = member
      bucket  = bucket
    }])
  }

  bucket = google_storage_bucket.buckets[each.value.bucket].name
  role   = each.value.role
  member = each.value.member
}


output "bucket_names" {
  value = [for bucket in google_storage_bucket.buckets : bucket.name]
}

