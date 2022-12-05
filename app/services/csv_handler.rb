require 'csv'

# Handles the writting and reading of a .csv
class CsvHandler
  def initialize(file_path)
    @file_path = file_path
  end

  # Saves the passed data on each line
  # new_lines receives an 2D Array. Each inner array is converted to a .csv line
  def add_lines(new_lines)
    CSV.open(@file_path, 'ab') do |csv|
      new_lines.each do |line|
        csv << line
      end
    end
  end

  # Reads the last csv line. If empty returns nil
  def read_last_line
    CSV.read(@file_path).last
  end
end
