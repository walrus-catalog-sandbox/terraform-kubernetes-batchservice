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
  deployment = {
    retries = 4
    execute_strategy = {
      type = "periodic"
      periodic = {
        cron_expression = "*/1 * * * *"
      }
    }
  }

  containers = [
    {
      name = "pi"
      image = {
        name = "perl:5.34.0"
      }
      execute = {
        command = ["perl", "-Mbignum=bpi", "-wle", "print bpi(2000)"]
      }
    }
  ]
}

module "blocking" {
  source = "../.."

  infrastructure = {
    namespace = kubernetes_namespace_v1.example.metadata[0].name
  }

  # calculate 10 times, process 3 units at once, retry 4 times if failed.
  deployment = {
    parallelism = 3
    retries     = 4
    execute_strategy = {
      type = "periodic"
      periodic = {
        cron_expression   = "*/1 * * * *"
        keep_not_finished = false
      }
    }
  }

  containers = [
    {
      name = "alpine"
      image = {
        name = "alpine"
      }
      execute = {
        command = ["sh", "-c", "sleep 80"]
      }
    }
  ]
}

module "suspending" {
  source = "../.."

  infrastructure = {
    namespace = kubernetes_namespace_v1.example.metadata[0].name
  }

  # process 3 units at once, stop if any is done, retry 4 times if failed.
  deployment = {
    retries = 4
    execute_strategy = {
      type = "periodic"
      periodic = {
        cron_expression   = "*/1 * * * *"
        keep_not_finished = false
        suspend           = true
      }
    }
  }

  containers = [
    {
      name = "alpine"
      image = {
        name = "alpine"
      }
      execute = {
        command = ["sh", "-c", "echo Hello World"]
      }
    }
  ]
}
