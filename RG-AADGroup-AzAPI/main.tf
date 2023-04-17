terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 1"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "role_definition_name" {
  type    = string
  default = "contributor"
}

variable "resource_group_name" {
  type = string
  default = "rg1"
}

variable "parent_id" {
  type = string
  default = "/subscriptions/e380d55c-263f-4af2-8587-0bdd61044290/resourcegroups/rg1"
}

// Allowed values: AdminAssign, AdminExtend, AdminRemove, AdminRenew, AdminUpdate, SelfActivate, SelfDeactivate, SelfExtend, SelfRenew
variable "request_type" {
  type    = string
  default = "AdminAssign"
}

data "azurerm_role_definition" "role" {
  name = var.role_definition_name
}

variable "assignment_days" {
  type    = number
  default = 365
}

// Allowed values: AfterDateTime, AfterDuration, NoExpiration
variable "assignment_expiration_type" {
  type    = string
  default = "AfterDuration"
}

resource "azuread_group" "rg_contributor_group_1" {
  display_name     = "rg_contributor_group_1"
  mail_enabled     = false
  security_enabled = true
}

resource "azurerm_resource_group" "rg1" {
  name     = var.resource_group_name
  location = "eastus"
}

// Used to a) support short life time assignments automatically re-assigned and b) support a single start date that does not change
resource "time_rotating" "eligible_schedule_request_start_date" {
  rotation_days = floor(var.assignment_days / 2)
}

// Generate a new guid for the eligible schedule request whever principalId, roleDefinitionId or requestType changes
resource "random_uuid" "eligible_schedule_request_id" {
  keepers = {
    principalId         = azurerm_resource_group.rg1.id
    roleDefinitionId    = data.azurerm_role_definition.role.id
    requestType         = var.request_type
    startDateTime       = "${formatdate("YYYY-MM-DD", time_rotating.eligible_schedule_request_start_date.id)}T${formatdate("HH:mm:ss.0000000+02:00", time_rotating.eligible_schedule_request_start_date.id)}"
    duration            = "P${tostring(var.assignment_days)}D"
    resource_group_name = azurerm_resource_group.rg1.name
  }
}

resource "azapi_resource" "pim_assign_01" {
  type      = "Microsoft.Authorization/roleEligibilityScheduleRequests@2022-04-01-preview"
  name      = random_uuid.eligible_schedule_request_id.id
  parent_id = var.parent_id
  body = jsonencode({
    properties = {
      justification    = "Testing PIM Assignment"
      principalId      = azuread_group.rg_contributor_group_1.object_id
      requestType      = var.request_type
      roleDefinitionId = data.azurerm_role_definition.role.id
      scheduleInfo = {
        expiration = {
          duration = "P${tostring(var.assignment_days)}D"
          type     = var.assignment_expiration_type
        }
        startDateTime = "${formatdate("YYYY-MM-DD", time_rotating.eligible_schedule_request_start_date.id)}T${formatdate("HH:mm:ss.0000000+02:00", time_rotating.eligible_schedule_request_start_date.id)}"
      }
    }
  })
}
