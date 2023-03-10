\name{partition_by_kmeans}
\alias{partition_by_kmeans}
\title{
Partition by kmeans
}
\description{
Partition by kmeans
}
\usage{
partition_by_kmeans(mat, n_repeats = 10)
}
\arguments{

  \item{mat}{The similarity matrix.}
  \item{n_repeats}{Number of repeated runs of k-means.}

}
\details{
Since k-means clustering brings randomness, this function performs
k-means clustering several times (controlled by \code{n_repeats}) and uses the final consensus partitioning.

This function is used to set to the \code{partition_fun} argument in \code{\link{binary_cut}}.
}
\examples{
# There is no example
NULL

}
