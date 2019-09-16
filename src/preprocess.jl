#Author: Yavuz Faruk Bakman
#Date: 15/08/2019

function resizekern(source_size::Tuple{Int,Int}, dest_size::Tuple{Int,Int})
    # Blur before resizing to prevent aliasing (kernel size dependent on both source and target image size)
    σ = map((o,n)->0.75*o/n, source_size, dest_size)
    if first(σ) < 1
        return ImageFiltering.KernelFactors.gaussian(σ)
    else
        return ImageFiltering.KernelFactors.IIRGaussian(σ)
    end
end

function sizethatfits(original_size::Tuple{Int,Int},target_shape::Tuple{Int,Int})
    if original_size[1] > original_size[2]
        target_img_size = (target_shape[1],floor(Int,target_shape[2]*(original_size[2]/original_size[1])))
    else
        target_img_size = (floor(Int,target_shape[1]*(original_size[1]/original_size[2])),target_shape[2])
    end
    return target_img_size
end

function loadResizePadImageToFit(img_path::String, target_img_shape::Tuple{Int,Int})
    img = FileIO.load(img_path)
    img_size = size(img)
    target_img_size = sizethatfits(img_size,target_img_shape)
    kern = resizekern(img_size,target_img_size)
    return resizePadImageToFit(img, target_img_size, target_img_shape, kern)
end

"""
    resizePadImageToFit(img_path::String, target_img_shape::Tuple{Int,Int}, kern::Tuple{ImageFiltering.KernelFactors.ReshapedOneD,ImageFiltering.KernelFactors.ReshapedOneD})

Loads and prepares (resizes + pads) an image to fit within a given shape.
Returns the image and the padding.
"""
function resizePadImageToFit(img::Array{T}, target_img_size::Tuple{Int,Int},
        target_img_shape::Tuple{Int,Int},
        kern::Tuple{ImageFiltering.KernelFactors.ReshapedOneD,ImageFiltering.KernelFactors.ReshapedOneD}) where {T<:ColorTypes.Color}

    imgr = ImageTransformations.imresize(ImageFiltering.imfilter(img, kern, NA()), target_img_size)

    # Determine top and left padding
    vpad_top = floor(Int,(target_img_shape[1]-target_img_size[1])/2)
    hpad_left = floor(Int,(target_img_shape[2]-target_img_size[2])/2)

    # Determine bottom and right padding accounting for rounding of top and left (to ensure accuate result image size if source has odd dimensions)
    vpad_bottom = target_img_shape[1] - (vpad_top + target_img_size[1])
    hpad_right = target_img_shape[2] - (hpad_left + target_img_size[2])

    padding = [hpad_left,vpad_top,hpad_right,vpad_bottom]

    # Pad image
    return padarray(imgr, Fill(zero(eltype(img)),(vpad_top,hpad_left),(vpad_bottom,hpad_right))), padding
end


function load(ds::LabelledImageDataset, settings::Settings; limitfirst::Int = -1)
    if limitfirst > 0
        @info "Loading images from $(ds.name) dataset into memory"
        numimages = limitfirst
    else
        @info "Loading first $numimages images from $(ds.name) dataset into memory"
        numimages = length(ds.image_paths)
    end
    kern = resizekern(ds.image_size_lims,settings.image_shape)

    firstimg, padding = loadResizePadImageToFit(ds.image_paths[1], settings.image_shape)
    imgsize = size(firstimg)

    lds = LoadedDataset(
        imagestack_matrix = Array{Float32}(undef,imgsize[1],imgsize[2],settings.image_channels,numimages),
        paddings = Vector{Vector{Int}}(undef,0)
    )

    ProgressMeter.@showprogress 0.25 "Loading images..." for i in 1:numimages
        img = FileIO.load(ds.image_paths[i])
        img_size = size(img)
        target_img_size = sizethatfits(img_size, settings.image_shape)
        img_resized, padding = resizePadImageToFit(img, target_img_size, settings.image_shape, kern)
        lds.imagestack_matrix[:,:,:,i] = collect(permutedims(channelview(img_resized)[1:settings.image_channels,:,:],[2,3,1]))
        push!(lds.paddings, padding)
    end
    return lds
end
