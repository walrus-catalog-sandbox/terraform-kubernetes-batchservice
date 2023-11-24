#
# Contextual Fields
#

variable "context" {
  description = <<-EOF
Receive contextual information. When Walrus deploys, Walrus will inject specific contextual information into this field.

Examples:
```
context:
  project:
    name: string
    id: string
  environment:
    name: string
    id: string
  resource:
    name: string
    id: string
```
EOF
  type        = map(any)
  default     = {}
}

#
# Infrastructure Fields
#

variable "infrastructure" {
  description = <<-EOF
Specify the infrastructure information for deploying.

Examples:
```
infrastructure:
  namespace: string, optional
  gpu_vendor: string, optional
```
EOF
  type = object({
    namespace  = optional(string)
    gpu_vendor = optional(string, "nvidia.com")
  })
  default = {}
}

#
# Deployment Fields
#

variable "task" {
  description = <<-EOF
Specify the task action, like execution, security and so on.

Examples:
```
task:
  mode: once/periodic
  periodic:
    cron_expression: string
    timezone: string, optional           # https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
    suspend: bool, optional
    keep_unfinished: bool, optional      # when set to true, if the previous task has not been completed, the new task will not be launched even when the scheduling time arrives
  timeout: number, optional
  completions: number, optional
  parallelism: number, optional
  retries: number, optional
  cleanup_finished: bool, optional       # cleanup the finished task after 5m
  keep_failed_process: bool, optional    # when set to true, the failed process will not be restarted
  fs_group: number, optional
  sysctls:
  - name: string
    value: string
```
EOF
  type = object({
    mode = optional(string, "once")
    periodic = optional(object({
      cron_expression = string
      timezone        = optional(string)
      suspend         = optional(bool, false)
      keep_unfinished = optional(bool, false)
    }))
    timeout             = optional(number, 300)
    completions         = optional(number)
    parallelism         = optional(number)
    retries             = optional(number, 6)
    cleanup_finished    = optional(bool, false)
    keep_failed_process = optional(bool, true)
    fs_group            = optional(number)
    sysctls = optional(list(object({
      name  = string
      value = string
    })))
  })
  default = {
    mode                = "once"
    timeout             = 300
    retries             = 6
    cleanup_finished    = false
    keep_failed_process = true
  }
}

variable "containers" {
  description = <<-EOF
Specify the container items to deploy.

Examples:
```
containers:
- profile: init/run
  image: string
  execute:
    working_dir: string, optional
    command: list(string), optional
    args: list(string), optional
    readonly_rootfs: bool, optional
    as_user: number, optional
    as_group: number, optional
  resources:
    cpu: number, optional               # in oneCPU, i.e. 0.25, 0.5, 1, 2, 4
    memory: number, optional            # in megabyte
    gpu: number, optional               # in oneGPU, i.e. 1, 2, 4
  envs:
  - name: string
    value: string, optional             # accpet changed and restart
    value_refer:                        # donot accpet changed
      schema: string
      params: map(any)
  files:
  - path: string
    mode: string, optional
    content: string, optional           # accpet changed but not restart
    content_refer:                      # donot accpet changed
      schema: string
      params: map(any)
  mounts:
  - path: string
    readonly: bool, optional
    subpath: string, optional
    volume: string, optional            # shared between containers if named, otherwise exclusively by this container
    volume_refer:
      schema: string
      params: map(any)
  checks:
  - type: execute/tcp/grpc/http/https
    delay: number, optional
    interval: number, optional
    timeout: number, optional
    retries: number, optional
    teardown: bool, optional
    execute:
      command: list(string)
    tcp:
      port: number
    grpc:
      port: number
      service: string, optional
    http:
      port: number
      headers: map(string), optional
      path: string, optional
    https:
      port: number
      headers: map(string), optional
      path: string, optional
```
EOF
  type = list(object({
    profile = optional(string, "run")
    image   = string
    execute = optional(object({
      working_dir     = optional(string)
      command         = optional(list(string))
      args            = optional(list(string))
      readonly_rootfs = optional(bool, false)
      as_user         = optional(number)
      as_group        = optional(number)
    }))
    resources = optional(object({
      cpu    = optional(number, 0.25)
      memory = optional(number, 256)
      gpu    = optional(number)
    }))
    envs = optional(list(object({
      name  = string
      value = optional(string)
      value_refer = optional(object({
        schema = string
        params = map(any)
      }))
    })))
    files = optional(list(object({
      path    = string
      mode    = optional(string, "0644")
      content = optional(string)
      content_refer = optional(object({
        schema = string
        params = map(any)
      }))
    })))
    mounts = optional(list(object({
      path     = string
      readonly = optional(bool, false)
      subpath  = optional(string)
      volume   = optional(string)
      volume_refer = optional(object({
        schema = string
        params = map(any)
      }))
    })))
    checks = optional(list(object({
      type     = string
      delay    = optional(number, 0)
      interval = optional(number, 10)
      timeout  = optional(number, 1)
      retries  = optional(number, 1)
      teardown = optional(bool, false)
      execute = optional(object({
        command = list(string)
      }))
      tcp = optional(object({
        port = number
      }))
      grpc = optional(object({
        port    = number
        service = optional(string)
      }))
      http = optional(object({
        port    = number
        headers = optional(map(string))
        path    = optional(string, "/")
      }))
      https = optional(object({
        port    = number
        headers = optional(map(string))
        path    = optional(string, "/")
      }))
    })))
  }))
  validation {
    condition     = length(var.containers) > 0
    error_message = "containers must be at least one"
  }
  validation {
    condition     = alltrue([for c in var.containers : try(c.profile == "" || contains(["init", "run"], c.profile), true)])
    error_message = "profile must be init or run"
  }
}
