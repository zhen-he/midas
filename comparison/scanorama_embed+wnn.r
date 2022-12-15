source("/root/workspace/code/sc-transformer/preprocess/utils.R")
setwd("/root/workspace/code/sc-transformer/")
library(gridExtra)
library(RColorBrewer)

parser <- ArgumentParser()
parser$add_argument("--task", type = "character", default = "dogma_full")
parser$add_argument("--method", type = "character", default = "scanorama_embed+wnn")
parser$add_argument("--exp", type = "character", default = "e0")
parser$add_argument("--model", type = "character", default = "default")
parser$add_argument("--init_model", type = "character", default = "sp_00001899")
o <- parser$parse_known_args()[[1]]

config <- parseTOML("configs/data.toml")[[o$task]]
subset_names <- basename(config$raw_data_dirs)
subset_ids <- sapply(seq_along(subset_names) - 1, toString)
input_dirs <- pj("result", o$task, o$exp, o$model, "predict", o$init_model, paste0("subset_", subset_ids))
pp_dir <- pj("data", "processed", o$task)
output_dir <- pj("result", "comparison", o$task, o$method)
mkdir(output_dir, remove_old = F)
label_paths <- pj(config$raw_data_dirs, "label_seurat", "l1.csv")

K <- parseTOML("configs/model.toml")[["default"]]$dim_c
l <- 7.5  # figure size
L <- 10   # figure size
m <- 0.5  # legend margin

rna_list <- list()
atac_list <- list()
adt_list <- list()
cell_name_list <- list()
label_list <- list()
subset_name_list <- list()
S <- length(subset_names)
for (i in seq_along(subset_names)) {
    subset_name <- subset_names[i]
    rna_dir  <- pj(input_dirs[i], "x", "rna")
    atac_dir <- pj(input_dirs[i], "x", "atac")
    adt_dir  <- pj(input_dirs[i], "x", "adt")
    fnames <- dir(path = rna_dir, pattern = ".csv$")
    fnames <- str_sort(fnames, decreasing = F)

    rna_subset_list <- list()
    atac_subset_list <- list()
    adt_subset_list <- list()
    N <- length(fnames)
    for (n in seq_along(fnames)) {
        message(paste0("Loading Subset ", i, "/", S, ", File ", n, "/", N))
        rna_subset_list[[n]] <- read.csv(file.path(rna_dir, fnames[n]), header = F)
        atac_subset_list[[n]] <- read.csv(file.path(atac_dir, fnames[n]), header = F)
        adt_subset_list[[n]] <- read.csv(file.path(adt_dir, fnames[n]), header = F)
    }
    rna_list[[subset_name]] <- bind_rows(rna_subset_list)
    atac_list[[subset_name]] <- bind_rows(atac_subset_list)
    adt_list[[subset_name]] <- bind_rows(adt_subset_list)

    cell_name_list[[subset_name]] <- read.csv(pj(pp_dir, paste0("subset_", subset_ids[i]),
        "cell_names.csv"), header = T)[, 2]
    label_list[[subset_name]] <- read.csv(label_paths[i], header = T)[, 2]
    subset_name_list[[subset_name]] <- rep(subset_name, length(cell_name_list[[subset_name]]))
}

cell_name <- do.call("c", unname(cell_name_list))

rna <- t(data.matrix(bind_rows(rna_list)))
colnames(rna) <- cell_name
rownames(rna) <- read.csv(pj(pp_dir, "feat", "feat_names_rna.csv"), header = T)[, 2]

adt <- t(data.matrix(bind_rows(adt_list)))
colnames(adt) <- cell_name
rownames(adt) <- read.csv(pj(pp_dir, "feat", "feat_names_adt.csv"), header = T)[, 2]

# remove missing features
rna_mask_list <- list()
adt_mask_list <- list()
for (i in seq_along(subset_names)) {
    subset_name <- subset_names[i]
    rna_mask_list[[subset_name]] <- read.csv(pj(pp_dir, paste0("subset_", subset_ids[i]),
        "mask", "rna.csv"), header = T)[, -1]
    adt_mask_list[[subset_name]] <- read.csv(pj(pp_dir, paste0("subset_", subset_ids[i]),
        "mask", "adt.csv"), header = T)[, -1]
}
rna_mask <- as.logical(apply(data.matrix(bind_rows(rna_mask_list)), 2, prod))
adt_mask <- as.logical(apply(data.matrix(bind_rows(adt_mask_list)), 2, prod))
rna <- rna[rna_mask, ]
adt <- adt[adt_mask, ]


obj <- CreateSeuratObject(counts = rna, assay = "rna")
obj[["adt"]] <- CreateAssayObject(counts = adt)

atac <- t(data.matrix(bind_rows(atac_list)))
# h <- nrow(atac)
# w <- ncol(atac)
# atac[] <- rbinom(n = h * w, size = 1, prob = atac)
# atac <- (atac > pmax(matrix(rowMeans(atac), h, w, byrow = F),
#                            matrix(colMeans(atac), h, w, byrow = T))) * 1
colnames(atac) <- cell_name
rownames(atac) <- read.csv(pj(pp_dir, "feat", "feat_names_atac.csv"), header = T)[, 2]
obj[["atac"]] <- CreateChromatinAssay(counts = atac)
# annotation <- GetGRangesFromEnsDb(EnsDb.Hsapiens.v86)
# seqlevelsStyle(annotation) <- "UCSC"
# genome(annotation) <- "hg38"
# obj[["atac"]] <- CreateChromatinAssay(counts = atac, genome = 'hg38', annotation = annotation)

obj@meta.data$l1 <- do.call("c", unname(label_list))
obj@meta.data$batch <- factor(x = do.call("c", unname(subset_name_list)), levels = subset_names)
table(obj@meta.data$batch)[unique(obj@meta.data$batch)]

obj
obj <- subset(obj, subset = nCount_atac > 0 & nCount_rna > 0 & nCount_adt > 0)
obj

rna_assay_list <- list()
atac_assay_list <- list()
adt_assay_list <- list()

rna_gene_list <- list()
atac_gene_list <- list()
adt_gene_list <- list()

for (i in seq_along(subset_names)) {
    batch <- subset_names[i]
    rna_assay_list[[i]] <- t(as.matrix(obj$rna@counts[, obj@meta.data$batch == batch]))
    adt_assay_list[[i]] <- t(as.matrix(obj$adt@counts[, obj@meta.data$batch == batch]))
    atac_assay_list[[i]] <- t(as.matrix(obj$atac@counts[, obj@meta.data$batch == batch]))

    rna_gene_list[[i]] <- colnames(rna_assay_list[[i]])
    adt_gene_list[[i]] <- colnames(adt_assay_list[[i]])
    atac_gene_list[[i]] <- colnames(atac_assay_list[[i]])
}

## r_to_python
library(Matrix)
library(reticulate)
scanorama <- import('scanorama')

# rna
integrated.rna <- scanorama$integrate(rna_assay_list, rna_gene_list, dimred = K)
scanorama_rna <- do.call(rbind, integrated.rna[[1]])
colnames(scanorama_rna) <- paste0("scanorama_", seq_len(ncol(scanorama_rna)))
rownames(scanorama_rna) <- colnames(obj)
pcs_scanorama_rna <- prcomp(x = t(scanorama_rna))
obj$scanorama_rna <- CreateDimReducObject(
    embeddings = pcs_scanorama_rna$rotation,
    loadings = pcs_scanorama_rna$x,
    stdev = pcs_scanorama_rna$sdev,
    key = "Scanorama_rna_PC",
    assay = "rna"
)

# adt
integrated.adt <- scanorama$integrate(adt_assay_list, adt_gene_list, dimred = K)
scanorama_adt <- do.call(rbind, integrated.adt[[1]])
colnames(scanorama_adt) <- paste0("scanorama_", seq_len(ncol(scanorama_adt)))
rownames(scanorama_adt) <- colnames(obj)
pcs_scanorama_adt <- prcomp(x = t(scanorama_adt))
obj$scanorama_adt <- CreateDimReducObject(
    embeddings = pcs_scanorama_adt$rotation,
    loadings = pcs_scanorama_adt$x,
    stdev = pcs_scanorama_adt$sdev,
    key = "Scanorama_adt_PC",
    assay = "adt"
)

# atac
integrated.atac <- scanorama$integrate(atac_assay_list, atac_gene_list, dimred = K)
scanorama_atac <- do.call(rbind, integrated.atac[[1]])
colnames(scanorama_atac) <- paste0("scanorama_", seq_len(ncol(scanorama_atac)))
rownames(scanorama_atac) <- colnames(obj)
pcs_scanorama_atac <- prcomp(x = t(scanorama_atac))
obj$scanorama_atac <- CreateDimReducObject(
    embeddings = pcs_scanorama_atac$rotation,
    loadings = pcs_scanorama_atac$x,
    stdev = pcs_scanorama_atac$sdev,
    key = "Scanorama_atac_PC",
    assay = "atac"
)

# wnn
obj <- FindMultiModalNeighbors(obj, list("scanorama_atac", "scanorama_rna", "scanorama_adt"),
                                    list(1:K, 1:K, 1:K))

# save connectivity matrices for benchmarking
connectivities <- obj$wsnn
diag(connectivities) <- 0
invisible(writeMM(connectivities, pj(output_dir, "connectivities.mtx")))

obj <- RunUMAP(obj, nn.name = "weighted.nn", reduction.name = "umap")
SaveH5Seurat(obj, pj(output_dir, "obj.h5seurat"), overwrite = TRUE)

# obj <- LoadH5Seurat(pj(output_dir, "obj.h5seurat"), assays = "adt", reductions = "umap")

# dim_plot(obj, w = 4*l, h = l, reduction = "umap",
#     split.by = "batch", group.by = "batch", label = F,
#     repel = T, label.size = 4, pt.size = 0.5, cols = NULL,
#     title = o$method, legend = F,
#     save_path = pj(output_dir, paste0(o$method, "_split_batch")))

# dim_plot(obj, w = 4*l+m, h = l, reduction = "umap",
#     split.by = "batch", group.by = "l1", label = F,
#     repel = T, label.size = 4, pt.size = 0.5, cols = dcols,
#     title = o$method, legend = T,
#     save_path = pj(output_dir, paste0(o$method, "_split_label")))

# dim_plot(obj, w = L+m, h = L, reduction = "umap",
#     split.by = NULL, group.by = "batch", label = F,
#     repel = T, label.size = 4, pt.size = 0.1, cols = NULL,
#     title = o$method, legend = T,
#     save_path = pj(output_dir, paste0(o$method, "_merged_batch")))

# dim_plot(obj, w = L+m, h = L, reduction = "umap",
#     split.by = NULL, group.by = "l1", label = F,
#     repel = T, label.size = 4, pt.size = 0.1, cols = dcols,
#     title = o$method, legend = T,
#     save_path = pj(output_dir, paste0(o$method, "_merged_label")))

# obj <- LoadH5Seurat(pj(output_dir, "obj.h5seurat"), assays = "adt", reductions = "umap")

dim_plot(obj, w = L, h = L, reduction = 'umap', no_axes = T,
    split.by = NULL, group.by = "batch", label = F, repel = T, label.size = 4, pt.size = 0.1, cols = col_4, legend = F,
    save_path = pj(output_dir, paste(o$method, "merged_batch", sep = "_")))

dim_plot(obj, w = L, h = L, reduction = 'umap', no_axes = T,
    split.by = NULL, group.by = "l1", label = F, repel = T, label.size = 4, pt.size = 0.1, cols = col_8, legend = F,
    save_path = pj(output_dir, paste(o$method, "merged_label", sep = "_")))
