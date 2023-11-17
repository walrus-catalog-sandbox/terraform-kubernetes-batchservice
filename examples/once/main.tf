terraform {
  required_version = ">= 1.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23.0"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "kubernetes_namespace_v1" "example" {
  metadata {
    name = "once-task"
  }
}

module "non_parallel" {
  source = "../.."

  infrastructure = {
    namespace = kubernetes_namespace_v1.example.metadata[0].name
  }

  # calculate 1 time, retry 4 times if failed.
  task = {
    retries = 4
  }

  containers = [
    {
      image = "perl:5.34.0"
      execute = {
        command = ["perl", "-Mbignum=bpi", "-wle", "print bpi(2000)"]
      }
    }
  ]
}

module "parallel" {
  source = "../.."

  infrastructure = {
    namespace = kubernetes_namespace_v1.example.metadata[0].name
  }

  # calculate 10 times, process 3 units at once, retry 4 times if failed.
  task = {
    completions = 10
    parallelism = 3
    retries     = 4
  }

  containers = [
    {
      image = "perl:5.34.0"
      execute = {
        command = ["perl", "-Mbignum=bpi", "-wle", "print bpi(2000)"]
      }
    }
  ]
}

module "queue" {
  source = "../.."

  infrastructure = {
    namespace = kubernetes_namespace_v1.example.metadata[0].name
  }

  # process 3 units at once, stop if any is done, retry 4 times if failed.
  task = {
    parallelism = 3
    retries     = 4
  }

  containers = [
    {
      image = "perl:5.34.0"
      execute = {
        command = ["perl", "-Mbignum=bpi", "-wle", "print bpi(2000)"]
      }
    }
  ]
}
