terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3"
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

variable "resource_group_name" {
  type = string
}

variable "user_principal_name" {
  type = string
}

variable "role_definition_name" {
  type = string
}

// Allowed values: AdminAssign, AdminExtend, AdminRemove, AdminRenew, AdminUpdate, SelfActivate, SelfDeactivate, SelfExtend, SelfRenew
variable "request_type" {
  type    = string
  default = "AdminUpdate"
}

variable "deployment_name" {
  type    = string
  default = null
}

variable "assignment_days" {
  type    = number
  default = 365
}

// Get role from data resource, instead of hard coding
data "azurerm_role_definition" "role" {
  name = var.role_definition_name
}

data "azuread_user" "user1" {
  user_principal_name = var.user_principal_name
}

resource "azurerm_resource_group" "rg1" {
  name     = "rg1"
  location = "eastus"
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

// Used to a) support short life time assignments automatically re-assigned and b) support a single start date that does not change
resource "time_rotating" "eligible_schedule_request_start_date" {
  rotation_days = floor(var.assignment_days / 2)
}

// Deploy the eligible schedule request using ARM template
resource "azurerm_resource_group_template_deployment" "eligible_schedule_request" {
  name                = var.deployment_name == null ? random_uuid.eligible_schedule_request_id.id : var.deployment_name
  resource_group_name = var.resource_group_name
  deployment_mode     = "Incremental"
  template_content    = file("${path.module}/pim_assignment.json")

  // Send parameters to ARM template
  parameters_content = jsonencode({
    "principalId" = {
      value = data.azuread_user.user1.object_id
    },
    "roleDefinitionId" = {
      value = data.azurerm_role_definition.role.id
    },
    "requestType" = {
      value = var.request_type
    },
    "id" = {
      value = random_uuid.eligible_schedule_request_id.id
    }
    "startDateTime" = {
      value = "${formatdate("YYYY-MM-DD", time_rotating.eligible_schedule_request_start_date.id)}T${formatdate("HH:mm:ss.0000000+02:00", time_rotating.eligible_schedule_request_start_date.id)}"
    }
    "duration" = {
      value = "P${tostring(var.assignment_days)}D"
    }
  })
}
