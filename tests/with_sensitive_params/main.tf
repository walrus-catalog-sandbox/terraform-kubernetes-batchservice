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

module "once" {
  source = "../.."

  infrastructure = {
    namespace = "defualt"
  }

  task = {
    mode    = "once"
    retries = 4
    sysctls = [
      {
        name  = "net.ipv4.tcp_syncookies"
        value = sensitive("1") # sensitive value
      }
    ]
  }

  containers = [
    #
    # Init Container
    #
    {
      profile = sensitive("init")
      image   = "busybox"
      execute = {
        command = [
          "sh",
          sensitive("-c"),
          "cp /var/run/dir1/logs.txt /var/run/dir2/; cat /var/run/dir2/logs.txt"
        ]
      }
      envs = [
        {
          name  = sensitive("ENV1") # sensitive value
          value = "VALUE1"
        }
      ]
      resources = {
        cpu    = sensitive(0.1) # sensitive value
        memory = 100
      }
      files = [
        {
          path    = sensitive("/var/run/dir1/logs.txt") # sensitive value
          content = "Hello"
        }
      ]
      mounts = [
        {
          path   = "/var/run/dir2"
          volume = sensitive("data2") # sensitive value
        }
      ]
    },
    #
    # Run Container
    #
    {
      image = sensitive("perl:5.34.0") # sensitive value
      execute = {
        command = ["perl", "-Mbignum=bpi", "-wle", "print bpi(2000)"]
      }
      resources = {
        cpu    = 0.1
        memory = sensitive(100) # sensitive value
      }
      envs = [
        {
          name  = "ENV1"
          value = sensitive("VALUE1") # sensitive value
        }
      ]
      files = [
        {
          path    = "/usr/share/nginx/html/index.html"
          content = sensitive("<html><h1>Hello</h1></html") # sensitive value
        }
      ]
      mounts = [
        {
          path = sensitive("/var/run/dir1") # sensitive value
        },
        {
          path   = "/var/run/dir2"
          volume = "data2"
        }
      ]
      checks = [
        {
          type  = "http"
          delay = sensitive(10) # sensitive value
          http = {
            port = 80
            headers = {
              "X-Agent" = sensitive("localhost") # sensitive value
            }
          }
        }
      ]
    }
  ]
}

output "once_context" {
  value = module.once.context
}

output "once_refer" {
  value = nonsensitive(module.once.refer)
}

module "periodic" {
  source = "../.."

  infrastructure = {
    namespace = "defualt"
  }

  task = {
    mode = "periodic"
    periodic = {
      cron_expression = sensitive("*/1 * * * *")
    }
    retries = 4
    sysctls = [
      {
        name  = "net.ipv4.tcp_syncookies"
        value = sensitive("1") # sensitive value
      }
    ]
  }

  containers = [
    #
    # Init Container
    #
    {
      profile = sensitive("init")
      image   = "busybox"
      execute = {
        command = [
          "sh",
          sensitive("-c"),
          "cp /var/run/dir1/logs.txt /var/run/dir2/; cat /var/run/dir2/logs.txt"
        ]
      }
      envs = [
        {
          name  = sensitive("ENV1") # sensitive value
          value = "VALUE1"
        }
      ]
      resources = {
        cpu    = sensitive(0.1) # sensitive value
        memory = 100
      }
      files = [
        {
          path    = sensitive("/var/run/dir1/logs.txt") # sensitive value
          content = "Hello"
        }
      ]
      mounts = [
        {
          path   = "/var/run/dir2"
          volume = sensitive("data2") # sensitive value
        }
      ]
    },
    #
    # Run Container
    #
    {
      image = sensitive("perl:5.34.0") # sensitive value
      execute = {
        command = ["perl", "-Mbignum=bpi", "-wle", "print bpi(2000)"]
      }
      resources = {
        cpu    = 0.1
        memory = sensitive(100) # sensitive value
      }
      envs = [
        {
          name  = "ENV1"
          value = sensitive("VALUE1") # sensitive value
        }
      ]
      files = [
        {
          path    = "/usr/share/nginx/html/index.html"
          content = sensitive("<html><h1>Hello</h1></html") # sensitive value
        }
      ]
      mounts = [
        {
          path = sensitive("/var/run/dir1") # sensitive value
        },
        {
          path   = "/var/run/dir2"
          volume = "data2"
        }
      ]
      checks = [
        {
          type  = "http"
          delay = sensitive(10) # sensitive value
          http = {
            port = 80
            headers = {
              "X-Agent" = sensitive("localhost") # sensitive value
            }
          }
        }
      ]
    }
  ]
}

output "periodic_context" {
  value = module.periodic.context
}

output "periodic_refer" {
  value = nonsensitive(module.periodic.refer)
}
