module ChunkyPNG
  class PixelMatrix
    
    # Methods for encoding a PixelMatrix into a PNG datastream
    #
    module PNGEncoding

      def write(io, constraints = {})
        to_datastream(constraints).write(io)
      end

      def save(filename, constraints = {})
        File.open(filename, 'w') { |io| write(io, constraints) }
      end
      
      def to_blob(constraints = {})
        to_datastream(constraints).to_blob
      end
      
      alias :to_string :to_blob
      alias :to_s :to_blob

      # Converts this PixelMatrix to a datastream, so that it can be saved as a PNG image.
      # @param [Hash] constraints The constraints to use when encoding the matrix.
      def to_datastream(constraints = {})
        data = encode_png(constraints)
        ds = Datastream.new
        ds.header_chunk       = Chunk::Header.new(data[:header])
        ds.palette_chunk      = data[:palette_chunk]      if data[:palette_chunk]
        ds.transparency_chunk = data[:transparency_chunk] if data[:transparency_chunk]
        ds.data_chunks        = Chunk::ImageData.split_in_chunks(data[:pixelstream])
        ds.end_chunk          = Chunk::End.new
        return ds
      end

      protected
      
      def encode_png(constraints = {})
        encoding = determine_png_encoding(constraints)
        result = {}
        result[:header] = { :width => width, :height => height, :color => encoding[:color_mode] }

        if encoding[:color_mode] == ChunkyPNG::COLOR_INDEXED
          result[:palette_chunk]      = encoding[:palette].to_plte_chunk
          result[:transparency_chunk] = encoding[:palette].to_trns_chunk unless encoding[:palette].opaque?
        end

        result[:pixelstream] = encode_png_pixelstream(encoding[:color_mode], encoding[:palette])
        return result
      end

      def determine_png_encoding(constraints = {})
        encoding = constraints
        encoding[:palette]    ||= palette
        encoding[:color_mode] ||= encoding[:palette].best_colormode
        return encoding
      end

      def encode_png_pixelstream(color_mode = ChunkyPNG::COLOR_TRUECOLOR, palette = nil)

        pixel_encoder = case color_mode
          when ChunkyPNG::COLOR_TRUECOLOR       then lambda { |color| Color.truecolor_bytes(color) }
          when ChunkyPNG::COLOR_TRUECOLOR_ALPHA then lambda { |color| Color.truecolor_alpha_bytes(color) }
          when ChunkyPNG::COLOR_INDEXED         then lambda { |color| [palette.index(color)] }
          when ChunkyPNG::COLOR_GRAYSCALE       then lambda { |color| Color.grayscale_bytes(color) }
          when ChunkyPNG::COLOR_GRAYSCALE_ALPHA then lambda { |color| Color.grayscale_alpha_bytes(color) }
          else raise "Cannot encode pixels for this mode: #{color_mode}!"
        end

        if color_mode == ChunkyPNG::COLOR_INDEXED && !palette.can_encode?
          raise "This palette is not suitable for encoding!"
        end

        pixel_size = Color.bytesize(color_mode)

        stream   = ""
        previous_bytes = Array.new(pixel_size * width, 0)
        each_scanline do |line|
          unencoded_bytes = line.map(&pixel_encoder).flatten
          stream << encode_png_scanline_up(unencoded_bytes, previous_bytes, pixel_size).pack('C*')
          previous_bytes  = unencoded_bytes
        end
        return stream
      end

      def encode_png_scanline(filter, bytes, previous_bytes = nil, pixelsize = 3)
        case filter
        when ChunkyPNG::FILTER_NONE    then encode_png_scanline_none(    bytes, previous_bytes, pixelsize)
        when ChunkyPNG::FILTER_SUB     then encode_png_scanline_sub(     bytes, previous_bytes, pixelsize)
        when ChunkyPNG::FILTER_UP      then encode_png_scanline_up(      bytes, previous_bytes, pixelsize)
        when ChunkyPNG::FILTER_AVERAGE then encode_png_scanline_average( bytes, previous_bytes, pixelsize)
        when ChunkyPNG::FILTER_PAETH   then encode_png_scanline_paeth(   bytes, previous_bytes, pixelsize)
        else raise "Unknown filter type"
        end
      end

      def encode_png_scanline_none(original_bytes, previous_bytes = nil, pixelsize = 3)
        [ChunkyPNG::FILTER_NONE] + original_bytes
      end

      def encode_png_scanline_sub(original_bytes, previous_bytes = nil, pixelsize = 3)
        encoded_bytes = []
        original_bytes.length.times do |index|
          a = (index >= pixelsize) ? original_bytes[index - pixelsize] : 0
          encoded_bytes[index] = (original_bytes[index] - a) % 256
        end
        [ChunkyPNG::FILTER_SUB] + encoded_bytes
      end

      def encode_png_scanline_up(original_bytes, previous_bytes, pixelsize = 3)
        encoded_bytes = []
        original_bytes.length.times do |index|
          b = previous_bytes[index]
          encoded_bytes[index] = (original_bytes[index] - b) % 256
        end
        [ChunkyPNG::FILTER_UP] + encoded_bytes
      end
      
      def encode_png_scanline_average(original_bytes, previous_bytes, pixelsize = 3)
        encoded_bytes = []
        original_bytes.length.times do |index|
          a = (index >= pixelsize) ? original_bytes[index - pixelsize] : 0
          b = previous_bytes[index]
          encoded_bytes[index] = (original_bytes[index] - (a + b / 2).floor) % 256
        end
        [ChunkyPNG::FILTER_AVERAGE] + encoded_bytes
      end
      
      def encode_png_scanline_paeth(original_bytes, previous_bytes, pixelsize = 3)
        encoded_bytes = []
        original_bytes.length.times do |i|
          a = (i >= pixelsize) ? original_bytes[i - pixelsize] : 0
          b = previous_bytes[i]
          c = (i >= pixelsize) ? previous_bytes[i - pixelsize] : 0
          p = a + b - c
          pa = (p - a).abs
          pb = (p - b).abs
          pc = (p - c).abs
          pr = (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c)
          encoded_bytes[i] = (original_bytes[i] - pr) % 256
        end
        [ChunkyPNG::FILTER_PAETH] + encoded_bytes
      end
    end
  end
end
