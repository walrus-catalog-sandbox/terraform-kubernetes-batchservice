# Periodic Task Example

Start periodic task by root moudle.

```bash
# setup infra
$ tf apply -auto-approve \
  -target=kubernetes_namespace_v1.example

# create service
$ tf apply -auto-approve \
  -target=module.normal

$ tf apply -auto-approve \
  -target=module.blocking

$ tf apply -auto-approve \
  -target=module.suspending
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.23.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 2.23.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_normal"></a> [normal](#module\_normal) | ../.. | n/a |
| <a name="module_concurrent"></a> [concurrent](#module\_concurrent) | ../.. | n/a |
| <a name="module_suspend"></a> [suspend](#module\_suspend) | ../.. | n/a |

## Resources

| Name | Type |
|------|------|
| [kubernetes_namespace_v1.example](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace_v1) | resource |

## Inputs

No inputs.

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_normal_context"></a> [normal\_context](#output\_normal\_context) | n/a |
| <a name="output_normal_refer"></a> [normal\_refer](#output\_normal\_refer) | n/a |
| <a name="output_concurrent_context"></a> [concurrent\_context](#output\_concurrent\_context) | n/a |
| <a name="output_concurrent_refer"></a> [concurrent\_refer](#output\_concurrent\_refer) | n/a |
| <a name="output_suspend_context"></a> [suspend\_context](#output\_suspend\_context) | n/a |
| <a name="output_suspend_refer"></a> [suspend\_refer](#output\_suspend\_refer) | n/a |
<!-- END_TF_DOCS -->
