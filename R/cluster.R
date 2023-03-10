
# == title
# Cluster functional terms
#
# == param
# -mat A similarity matrix.
# -method Method for clustering the matrix.
# -control A list of parameters passed to the corresponding clustering function.
# -catch_error Internally used.
# -verbose Whether to print messages.
#
# == details
# The following methods are the default:
#
# -``kmeans`` see `cluster_by_kmeans`.
# -``pam`` see `cluster_by_pam`.
# -``dynamicTreeCut`` see `cluster_by_dynamicTreeCut`.
# -``mclust`` see `cluster_by_mclust`.
# -``apcluster`` see `cluster_by_apcluster`.
# -``hdbscan`` see `cluster_by_hdbscan`.
# -``leading_eigen`` see `cluster_by_igraph`.
# -``louvain`` see `cluster_by_igraph`.
# -``walktrap`` see `cluster_by_igraph`.
# -``MCL`` see `cluster_by_MCL`.
# -``binary_cut`` see `binary_cut`.
#
# Also the user-defined methods in `all_clustering_methods` can be used here.
#
# New clustering methods can be registered by `register_clustering_methods`.
#
# Please note it is better to directly call `cluster_terms` for clustering while not the individual ``cluster_by_*`` functions
# because `cluster_terms` does additional cluster label adjustment.
#
# == value
# A numeric vector of cluster labels (in numeric).
#
# If ``catch_error`` is set to ``TRUE`` and if the clustering produces an error,
# the function returns a ``try-error`` object.
cluster_terms = function(mat, method = "binary_cut", control = list(), catch_error = FALSE, 
	verbose = TRUE) {
	
	if(nrow(mat) != ncol(mat)) {
		stop_wrap("The matrix should be square.")
	}

	if(verbose) message(qq("Cluster @{nrow(mat)} terms by '@{method}'..."), appendLF = FALSE)
	flush.console()

	fun = get_clustering_method(method, control = control)
	
	t1 = Sys.time()
	oe = try(cl <- fun(mat), silent = TRUE)
	t2 = Sys.time()

	if(inherits(oe, "try-error")) {
		if(catch_error) {
			return(oe)
		} else {
			message("")
			stop(oe)
		}
	}

	t_diff = t2 - t1
	t_diff = format(t_diff)
	if(verbose) message(qq(" @{length(unique(cl))} clusters, used @{t_diff}."))

	if(length(unique(cl)) > 1) {
		if(method != "binary_cut") {
			#reorder the class labels
			class_mean = tapply(1:nrow(mat), cl, function(ind) {
				colMeans(mat[ind, , drop = FALSE])
			})
			class_mean = do.call(rbind, class_mean)
			ns = nrow(class_mean)

			class_dend = as.dendrogram(hclust(stats::dist(class_mean)))
			class_dend = reorder(class_dend, wts = rowSums(class_mean))
			map = structure(1:ns, names = order.dendrogram(class_dend))

			cl = map[as.character(cl)]
		}
	}

	attr(cl, "running_time") = t_diff

	return(cl)
}


# == title
# Cluster similarity matrix by k-means clustering
#
# == param
# -mat The similarity matrix.
# -max_k maximal k for k-means clustering.
# -... Other arguments passed to `stats::kmeans`.
#
# == details
# The best number of k for k-means clustering is identified according to the "elbow" or "knee" method on
# the distribution of within-cluster sum of squares (WSS) at each k.
#
# == value
# A vector of cluster labels (in numeric).
#
cluster_by_kmeans = function(mat, max_k = max(2, min(round(nrow(mat)/5), 100)), ...) {
	
	cl = list()
	wss = NULL

	if(max_k <= 2) {
		stop_wrap("`max_k` should be larger than 2.")
	}

	for (i in 2:max_k) {
		suppressWarnings(km <- kmeans(mat, centers = i, iter.max = 50))
		cl[[i - 1]] = km$cluster
		wss[i - 1] = sum(km$withinss)
	}
	best_km = min(elbow_finder(2:max_k, wss)[1], knee_finder(2:max_k, wss)[1])

	cl[[best_km - 1]]
}


# == title
# Cluster similarity matrix by pam clustering
#
# == param
# -mat The similarity matrix.
# -max_k maximal k for pam clustering.
# -... Other arguments passed to `fpc::pamk`.
#
# == details
# PAM is applied by `fpc::pamk` which can automatically select the best k.
#
# == value
# A vector of cluster labels (in numeric).
#
cluster_by_pam = function(mat, max_k = max(2, min(round(nrow(mat)/10), 100)), ...) {

	check_pkg("fpc", bioc = FALSE)

	best = fpc::pamk(mat, krange = 2:max_k, ...)
	best$pamobject$clustering
}

# https://stackoverflow.com/questions/2018178/finding-the-best-trade-off-point-on-a-curve
elbow_finder = function(x_values, y_values) {
  # Max values to create line
  max_x_x = max(x_values)
  max_x_y = y_values[which.max(x_values)]
  max_y_y = max(y_values)
  max_y_x = x_values[which.max(y_values)]
  max_df = data.frame(x = c(max_y_x, max_x_x), y = c(max_y_y, max_x_y))

  # Creating straight line between the max values
  fit = lm(max_df$y ~ max_df$x)

  # Distance from point to line
  distances = c()
  for(i in seq_along(x_values)) {
    distances = c(distances, abs(coef(fit)[2]*x_values[i] - y_values[i] + coef(fit)[1]) / sqrt(coef(fit)[2]^2 + 1^2))
  }

  # Max distance point
  x_max_dist = x_values[which.max(distances)]
  y_max_dist = y_values[which.max(distances)]

  return(c(x_max_dist, y_max_dist))
}

# https://raghavan.usc.edu//papers/kneedle-simplex11.pdf
knee_finder = function(x, y) {
	n = length(x)
	a = (y[n] - y[1])/(x[n] - x[1])
	b = y[1] - a*x[1]
	d = a*x - y
	x[which.max(d)]
}

# == title
# Cluster similarity matrix by dynamicTreeCut
#
# == param
# -mat The similarity matrix.
# -minClusterSize Minimal number of objects in a cluster. Pass to `dynamicTreeCut::cutreeDynamic`.
# -... Other arguments passed to `dynamicTreeCut::cutreeDynamic`.
#
# == value
# A vector of cluster labels (in numeric).
#
cluster_by_dynamicTreeCut = function(mat, minClusterSize = 5, ...) {

	check_pkg("dynamicTreeCut", bioc = FALSE)

	cl = dynamicTreeCut::cutreeDynamic(hclust(stats::dist(mat)), distM = 1 - mat, minClusterSize = minClusterSize, verbose = 0, ...)
	unname(cl)
}

# == title
# Cluster similarity matrix by graph community detection methods
#
# == param
# -mat The similarity matrix.
# -method The community detection method.
# -... Other arguments passed to the corresponding community detection function, see Details.
#
# == details
# The symmetric similarity matrix can be treated as an adjacency matrix and constructed as a graph/network with the similarity values as the weight of hte edges.
# Thus, clustering the similarity matrix can be treated as detecting clusters/modules/communities from the graph.
#
# Four methods implemented in igraph package can be used here:
#
# -``fast_greedy`` uses `igraph::cluster_fast_greedy`.
# -``leading_eigen`` uses `igraph::cluster_leading_eigen`.
# -``louvain`` uses `igraph::cluster_louvain`.
# -``walktrap`` uses `igraph::cluster_walktrap`.
#
# == value
# A vector of cluster labels (in numeric).
#
cluster_by_igraph = function(mat, 
    method = c("fast_greedy",
               "leading_eigen",
               "louvain",
               "walktrap"),
    ...) {

	check_pkg("igraph", bioc = FALSE)

	if(is.character(method)) {
		method = match.arg(method)[1]
		method = paste0("cluster_", method)
		method = getFromNamespace(method, ns = "igraph")
	}
	g = igraph::graph_from_adjacency_matrix(mat, mode = "upper", weighted = TRUE)

	imc = method(g, ...)
	as.vector(igraph::membership(imc))
}

# == title
# Cluster similarity matrix by mclust
#
# == param
# -mat The similarity matrix.
# -G Passed to the ``G`` argument in `mclust::Mclust`.
# -... Other arguments passed to `mclust::Mclust`.
#
# == value
# A vector of cluster labels (in numeric).
#
cluster_by_mclust = function(mat, G = seq_len(max(2, min(round(nrow(mat)/5), 100))), ...) {
	
	check_pkg("mclust", bioc = FALSE)

	mclustBIC = mclust::mclustBIC

	fit = mclust::Mclust(mat, G = G, verbose = FALSE, control = mclust::emControl(itmax = c(1000, 1000)), ...)

	unname(fit$classification)
}

# == title
# Cluster similarity matrix by apcluster
#
# == param
# -mat The similarity matrix.
# -s Passed to the ``s`` argument in `apcluster::apcluster`.
# -... Other arguments passed to `apcluster::apcluster`.
#
# == value
# A vector of cluster labels (in numeric).
#
cluster_by_apcluster = function(mat, s = apcluster::negDistMat(r = 2), ...) {
	
	check_pkg("apcluster", bioc = FALSE)

	x = apcluster::apcluster(s, mat, ...)
	cl = numeric(nrow(mat))
	for(i in seq_along(x@clusters)) {
		cl[x@clusters[[i]]] = i
	}
	cl
}


# == title
# Cluster similarity matrix by hdbscan
#
# == param
# -mat The similarity matrix.
# -minPts Passed to the ``minPts`` argument in `dbscan::hdbscan`.
# -... Other arguments passed to `dbscan::hdbscan`.
#
# == value
# A vector of cluster labels (in numeric).
#
cluster_by_hdbscan = function(mat, minPts = 5, ...) {
	
	check_pkg("dbscan", bioc = FALSE)

	dbscan::hdbscan(mat, minPts = minPts, ...)$cluster
}

# == title
# Cluster similarity matrix by MCL
#
# == param
# -mat The similarity matrix.
# -addLoops Passed to the ``addLoops`` argument in `MCL::mcl`.
# -... Other arguments passed to `MCL::mcl`.
#
# == value
# A vector of cluster labels (in numeric).
#
cluster_by_MCL = function(mat, addLoops = TRUE, ...) {
	
	check_pkg("MCL", bioc = FALSE)

	MCL::mcl(mat, addLoops = addLoops, allow1 = TRUE, ...)$Cluster
}
