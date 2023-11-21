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
    name = "periodic-task"
  }
}

module "normal" {
  source = "../.."

  infrastructure = {
    namespace = kubernetes_namespace_v1.example.metadata[0].name
  }

  # calculate 1 time, retry 4 times if failed.
  task = {
    mode = "periodic"
    periodic = {
      cron_expression = "*/1 * * * *"
    }
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

output "normal_context" {
  value = module.normal.context
}

output "normal_refer" {
  value = nonsensitive(module.normal.refer)
}

module "concurrent" {
  source = "../.."

  infrastructure = {
    namespace = kubernetes_namespace_v1.example.metadata[0].name
  }

  # calculate 10 times, process 3 units at once, retry 4 times if failed.
  task = {
    mode = "periodic"
    periodic = {
      cron_expression = "*/1 * * * *"
      keep_unfinished = true
    }
    parallelism = 3
    retries     = 4
  }

  containers = [
    {
      image = "alpine"
      execute = {
        command = ["sh", "-c", "sleep 80"]
      }
    }
  ]
}

output "concurrent_context" {
  value = module.concurrent.context
}

output "concurrent_refer" {
  value = nonsensitive(module.concurrent.refer)
}

module "suspend" {
  source = "../.."

  infrastructure = {
    namespace = kubernetes_namespace_v1.example.metadata[0].name
  }

  # process 3 units at once, stop if any is done, retry 4 times if failed.
  task = {
    mode = "periodic"
    periodic = {
      cron_expression = "*/1 * * * *"
      suspend         = true
    }
    retries = 4
  }

  containers = [
    {
      image = "alpine"
      execute = {
        command = ["sh", "-c", "echo Hello World"]
      }
    }
  ]
}

output "suspend_context" {
  value = module.suspend.context
}

output "suspend_refer" {
  value = nonsensitive(module.suspend.refer)
}
