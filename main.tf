# HOW TO USE:
# add following to your terraform config
#module "jupyter" {
#  source = "git@github.com:gumlooter/dockerized_jupyter.git"
#  count = 1 # 0 to turn it off
#  node_pool = google_container_node_pool.nodes
#  persistent_disk = "development-storage"
#  external_port = 443
#  public_url = "https://jupyter.example.com"
#  password = "sha1:74ba40f8a388:c913541b7ee99d15d5ed31d4226bf7838f83a50e"
#}

# calculate local vars based on input vars
locals {
  # decide to run or not to run based on count input
  onoff_switch = var.module_count != 1 ? 0 : 1
  args = concat(var.args, ["--NotebookApp.custom_display_url=${var.public_url}","--NotebookApp.password=${var.password}"])
}

# schedule Jupyter Notebook
resource "kubernetes_deployment" "jupyter" {
  # create resource only if there it's required
  count = local.onoff_switch

  metadata {
    name = var.deployment_name
  }
  
  # wait for gke node pool
  depends_on = [var.node_pool]

  spec {
    # we need only one replica of the service
    replicas = 1

    selector {
      match_labels = {
        app = var.app_name
      }
    }

    # pod configuration
    template {
      metadata {
        labels = {
          app = var.app_name
        }
      }

      spec {
        # attach persistent-disk to node
        volume {
          name= "persistent-volume"
          gce_persistent_disk {
            pd_name = var.persistent_disk
          }
        }

        # specify container 
        container {
          name = var.container_name
          image = var.image
          command = var.command
          args = local.args
          
          # all the jupyter settings
          env {
            name = var.envs[0].name
            value = var.envs[0].value
          }     
          
          # expose ports
          port {
            container_port = var.jupyter_port
          }

          # mount disk to container
          volume_mount {
            mount_path = var.persistent_mount_path
            name = "persistent-volume"
          }      
        }
      }      
    }
  }

  # terraform: give container more time to load image (it's huge)
  timeouts {
    create = var.terraform_timeout
  }
}

# add load balancer to drive external traffic to pod
resource "kubernetes_service" "jupyter_loadbalancer" {
  # create resource only if there it's required
  count = local.onoff_switch

  metadata {
    name = var.service_name
  }

  # wait for deployment
  depends_on = [kubernetes_deployment.jupyter]
  
  spec {
    selector = {
      # choose only jupyter
      app = var.app_name
    }
    
    port {
      # expose main port of jupyter container
      name = "main_port"
      port = var.external_port
      target_port = var.jupyter_port
    }    
  
    type = "LoadBalancer"
  }
}

# declare external ip 
output "external_ip" {
  value = kubernetes_service.jupyter_loadbalancer != [] ? kubernetes_service.jupyter_loadbalancer[0].load_balancer_ingress.0.ip : "0"
}
